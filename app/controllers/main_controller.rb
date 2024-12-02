# app/controllers/main_controller.rb

require 'streamio-ffmpeg'

class MainController < ApplicationController
  protect_from_forgery except: [:upload_audio, :confirm_transcription, :fetch_events, :fetch_action_logs]

  def main
    @action_log = flash[:action_log] || []
    @events = flash[:events] || []
    @transcription = flash[:transcription] || ""
    @skip_confirmation = flash[:skip_confirmation] == '1'
    render(template: "main_templates/home")
  end

  def upload_audio
    audio_file = params[:audio]
    hardcore_mode = params[:hardcore_mode] == '1'
    Rails.logger.debug "Received upload_audio request. Audio file present: #{audio_file.present?}, Hardcore Mode: #{hardcore_mode}"

    if audio_file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      Rails.logger.debug "Saving audio to: #{temp_audio_path}"
      begin
        FileUtils.mkdir_p(File.dirname(temp_audio_path))
        File.open(temp_audio_path, 'wb') { |file| file.write(audio_file.read) }
        Rails.logger.debug "Audio file saved successfully. Size: #{File.size(temp_audio_path)} bytes."

        if File.size(temp_audio_path) < 1000
          Rails.logger.error "Audio file too small: #{File.size(temp_audio_path)} bytes."
          File.delete(temp_audio_path)
          render json: { error: 'Audio file is too short. Please record a longer message.' }, status: :unprocessable_entity
          return
        end

        converted_audio_path = Rails.root.join('tmp', 'uploads', "converted_#{SecureRandom.uuid}.wav")
        movie = FFMPEG::Movie.new(temp_audio_path.to_s)
        transcoding_options = {
          audio_codec: "pcm_s16le",
          channels: 1,
          custom: %w(-ar 16000)
        }

        movie.transcode(converted_audio_path.to_s, transcoding_options) do |progress|
          if progress.finite?
            Rails.logger.debug "Transcoding progress: #{(progress * 100).to_i}%"
          else
            Rails.logger.warn "Transcoding progress: Infinity"
          end
        end

        Rails.logger.debug "Audio file converted successfully to WAV. Size: #{File.size(converted_audio_path)} bytes."

        openai_service = OpenaiService.new
        transcription = openai_service.transcribe_audio(audio_file_path: converted_audio_path.to_s)
        Rails.logger.debug "Transcription received: #{transcription}"

        if hardcore_mode
          Rails.logger.debug "Processing transcription in hardcore mode."
          result = process_transcription(transcription)
          Rails.logger.debug "process_transcription() method complete."

          if result[:success]
            flash[:action_log] = result[:action_log]
            flash[:transcription] = transcription
            render json: { success: true, action_log: result[:action_log], transcription: transcription }, status: :ok
          else
            Rails.logger.error "Transcription processing failed: #{result[:error]}"
            render json: { success: false, error: result[:error] }, status: :unprocessable_entity
          end
        else
          Rails.logger.debug "Returning transcription for manual confirmation."
          flash[:events] ||= []
          flash[:events] << { timestamp: Time.now.strftime("%H:%M:%S"), message: 'Transcription received for confirmation.' }
          render json: { transcription: transcription }, status: :ok
        end
      rescue FFMPEG::Error => e
        Rails.logger.error "FFmpeg transcoding failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: 'Failed to process the audio file.' }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error "Exception in upload_audio: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: 'An error occurred while processing the audio.' }, status: :internal_server_error
      ensure
        [temp_audio_path, converted_audio_path].each do |path|
          if path && File.exist?(path)
            File.delete(path)
            Rails.logger.debug "Temporary audio file #{path} deleted."
          end
        end
      end
    else
      render json: { error: 'No audio file uploaded.' }, status: :bad_request
    end
  end

  def confirm_transcription
    transcription = params[:transcription]
    hardcore_mode = params[:hardcore_mode] == '1'

    Rails.logger.debug "Received confirm_transcription request. Transcription: #{transcription}, Hardcore Mode: #{hardcore_mode}"

    if hardcore_mode
      result = process_transcription(transcription)
      if result[:success]
        flash[:action_log] = result[:action_log]
        flash[:transcription] = transcription
        render json: { success: true, message: 'Transcription processed successfully.' }, status: :ok
      else
        render json: { success: false, error: result[:error] }, status: :unprocessable_entity
      end
    else
      flash[:action_log] = ['Transcription confirmed by user.']
      flash[:transcription] = transcription
      render json: { success: true, message: 'Transcription confirmed.' }, status: :ok
    end
  end

  def fetch_events
    @events = flash[:events] || []
    render json: { events: @events.map { |event| event[:message] } }, status: :ok
  end

  def fetch_action_logs
    @action_log = flash[:action_log] || []
    render json: { action_logs: @action_log.map { |action| action[:message] } }, status: :ok
  end

  private

  def process_transcription(transcription)
    Rails.logger.debug "Starting process_transcription."
    openai_service = OpenaiService.new
    @note = transcription
    @todays_date = Date.today.strftime("%Y-%m-%d")
    @result = openai_service.classify_message(message: @note)

    notion_service = NotionService.new

    Rails.logger.debug "Parsing result: #{@result}"
    case @result
    when "note"
      process_note_transcription(notion_service, @note)
    when "task"
      process_task_transcription(notion_service, @note)
    when "recommendation"
      process_recommendation_transcription(notion_service, @note)
    when "ingredient"
      process_ingredient_transcription(notion_service, @note)
    when "recipe"
      process_recipe_transcription(notion_service, @note)
    else
      Rails.logger.error "Could not classify the transcription."
      return { success: false, error: 'Could not classify the transcription.' }
    end

    action_log = notion_service.action_log
    Rails.logger.debug "Item processing complete."
    return { success: true, action_log: action_log }
  rescue => e
    Rails.logger.error "Processing transcription failed: #{e.message}"
    return { success: false, error: 'An error occurred during processing.' }
  end
  
  def process_note_transcription(notion_service, note)
    openai_service = OpenaiService.new

    @body = openai_service.extract_note_body(message: note)
    @title = openai_service.extract_note_title(message: note)
    @related_entities = openai_service.extract_related_entities(message: @note) || []

    input_values = {
      title: @title,
      date: Date.today.strftime('%Y-%m-%d')
    }

    relations_hash = process_entities(notion_service, 'notes')

    children = [
      {
        object: 'block',
        type: 'paragraph',
        paragraph: {
          rich_text: [
            {
              type: 'text',
              text: {
                'content' => @body
              }
            }
          ]
        }
      }
    ]

    notion_service.create_page(
      database_key: :notes,
      input_values: input_values,
      relations: relations_hash,
      children: children
    )
  end

  def process_task_transcription(notion_service, note)
    openai_service = OpenaiService.new

    @task = openai_service.extract_task_summary(message: note)
    @deadline = openai_service.extract_deadline(message: note)
    @action_date = openai_service.extract_action_date(message: note)
    @related_entities = openai_service.extract_related_entities(message: note) || []

    input_values = {
      title: @task,
      deadline: @deadline,
      action_date: @action_date,
      status: 'Next'
    }

    relations_hash = process_entities(notion_service, 'tasks')

    notion_service.create_page(
      database_key: :tasks,
      input_values: input_values,
      relations: relations_hash
    )
  end

  def process_recommendation_transcription(notion_service, note)
    openai_service = OpenaiService.new

    @recommendation = openai_service.extract_recommendation_summary(message: note)
    @recommendation_type = openai_service.extract_recommendation_type(message: note)
    @related_entities = openai_service.extract_related_entities(message: note) || []

    input_values = {
      title: @recommendation
    }

    relations_hash = process_entities(notion_service, 'recommendations')

    notion_service.create_page(
      database_key: :recommendations,
      input_values: input_values,
      relations: relations_hash
    )
  end

  def process_ingredient_transcription(notion_service, note)
    openai_service = OpenaiService.new

    @ingredients = openai_service.extract_ingredients(message: note) || []

    update_values = lambda do |page, item|
      current_amount = notion_service.get_property_value(page: page, property_name: SCHEMA[:ingredients][:properties][:amount_needed][:name]) || 0
      new_amount = current_amount + item['quantity'].to_i
      { amount_needed: new_amount }
    end

    notion_service.update_items(:ingredients, @ingredients, update_values)
  end

  def process_recipe_transcription(notion_service, note)
    openai_service = OpenaiService.new

    @recipes = openai_service.extract_recipes(message: note) || []

    update_values = lambda do |_page, _item|
      { planned: true }
    endbi

    notion_service.update_items(:recipes, @recipes, update_values)
  end

  def process_entities(notion_service, database_key)
    relations_hash = {}
    @related_entities.each do |entity|
      relation_field = get_relation_field_for_entity_type(entity['type'], database_key)
      next unless relation_field

      relation_schema = SCHEMA[database_key.to_sym][:relations][relation_field.to_sym]
      entity_database_key = relation_schema[:database]

      page_id, match_type = notion_service.find_or_create_entity(
        name: entity['name'],
        database_key: entity_database_key
      )

      relations_hash[relation_field.to_sym] ||= []
      relations_hash[relation_field.to_sym] << page_id if page_id

      entity['page_id'] = page_id
      entity['match_type'] = match_type
    end
    relations_hash
  end

  def get_relation_field_for_entity_type(entity_type, database_key)
    SCHEMA[database_key.to_sym][:relations].each do |relation_key, relation_schema|
      if relation_schema[:database] == entity_type.pluralize.to_sym
        return relation_key.to_s
      end
    end
    nil
  end
end
