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
            Rails.logger.debug "Temporary audio file deleted."
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
    @todays_date = Date.today.strftime("%Y-%m-%d")
    Rails.logger.debug "Today's date: #{@todays_date}."
    @result = openai_service.classify_message(message: transcription)
  
    Rails.logger.debug "Result: #{@result}."
  
    notion_service = NotionService.new
  
    Rails.logger.debug "Parsing result: #{@result}"
    case @result
    when "note"
      Rails.logger.debug "Note transcription beginning."
      process_note_transcription(openai_service, notion_service, transcription)
      Rails.logger.debug "Note transcription successful."
    when "task"
      process_task_transcription(openai_service, notion_service, transcription)
    when "recommendation"
      process_recommendation_transcription(openai_service, notion_service, transcription)
    when "ingredient"
      process_ingredient_transcription(openai_service, notion_service, transcription)
    when "recipe"
      process_recipe_transcription(openai_service, notion_service, transcription)
    when "wordle"
      process_wordle_transcription(openai_service, notion_service, transcription)
    when "restaurant"
      process_restaurant_transcription(openai_service, notion_service, transcription)
    when "idea"
      process_idea_transcription(openai_service, notion_service, transcription)
    else
      Rails.logger.error "Could not classify the transcription."
      return { success: false, error: 'Could not classify the transcription.' }
    end
  
    action_log = notion_service.action_log
    Rails.logger.debug "Action log updated."
    return { success: true, action_log: action_log }
  rescue => e
    Rails.logger.error "Processing transcription failed: #{e.message}"
    return { success: false, error: 'An error occurred during processing.' }
  end  

  def process_note_transcription(openai_service, notion_service, note)
    body = openai_service.extract_note_body(message: note)
    title = openai_service.extract_note_title(message: note)
    related_entities = openai_service.extract_related_entities(message: note) || []

    recording = Recording.create(
      body: note,
      summary: title,
      recording_type: 'note',
      status: 'complete'
    )

    properties_hash = {
      'Meeting' => { type: 'title', value: title },
      'Date' => { type: 'date', value: Date.today.strftime('%Y-%m-%d') }
    }

    # Process related entities to construct relations
    related_entities.each do |entity|
      page_id, match_type = notion_service.find_or_create_entity(
        name: entity['name'],
        database_key: entity['type'].pluralize.to_sym
      )
      relation_name = case entity['type'].pluralize
                      when 'people' then 'People'
                      when 'companies' then 'Company'
                      when 'classes' then 'Class'
                      else nil
                      end
      next unless relation_name

      properties_hash[relation_name] ||= { type: 'relation', value: [] }
      properties_hash[relation_name][:value] << page_id
    end

    properties = notion_service.construct_properties(properties_hash)

    # Children (e.g., the body content)
    children = [
      {
        object: 'block',
        type: 'paragraph',
        paragraph: {
          rich_text: [
            {
              type: 'text',
              text: {
                'content' => body
              }
            }
          ]
        }
      }
    ]

    Rails.logger.debug "This is what functioning notes properties parameters look like: #{properties}"
    payload = {
      parent: { database_id: NotionService::DATABASES[:notes] },
      properties: properties,
      children: children
    }
    Rails.logger.debug "Final payload: \n#{payload}"
    response = notion_service.create_page(payload)
    page_id = response['id']

    Activity.create(
      recording_id: recording.id,
      page_id: page_id,
      page_url: notion_service.construct_notion_url(page_id),
      action: 'created',
      database_id: ENV.fetch("NOTES_DB_KEY"),
      database_name: 'notes',
      status: 'completed'
    )
  end

  def process_task_transcription(openai_service, notion_service, note)
    task = openai_service.extract_task_summary(message: note)
    deadline = openai_service.extract_deadline(message: note)
    action_date = openai_service.extract_action_date(message: note)
    related_entities = openai_service.extract_related_entities(message: note) || []

    recording = Recording.create(
      body: note,
      summary: task,
      recording_type: 'task',
      status: 'complete'
    )

    properties_hash = {
      'Name' => { type: 'title', value: task },
      'Deadline' => { type: 'date', value: deadline },
      'Action Date' => { type: 'date', value: action_date },
      'Status' => { type: 'status', value: 'Next' }
    }

    Rails.logger.debug "Task: #{task}, due #{deadline}, starting #{action_date}, related to #{related_entities}."
    # Process related entities to construct relations
    related_entities.each do |entity|
      Rails.logger.debug "Entity: #{entity['name']}, #{entity['type'].to_sym}."
      page_id, match_type = notion_service.find_or_create_entity(
        name: entity['name'],
        database_key: entity['type'].pluralize.to_sym
      )
      relation_name = case entity['type']
                      when 'person', 'people' then 'People'
                      when 'company', 'companies' then 'Company'
                      when 'class', 'classes' then 'Class'
                      else nil
                      end
      next unless relation_name

      properties_hash[relation_name] ||= { type: 'relation', value: [] }
      properties_hash[relation_name][:value] << page_id
    end

    properties = notion_service.construct_properties(properties_hash)

    payload = {
      parent: { database_id: NotionService::DATABASES[:tasks] },
      properties: properties
    }

    response = notion_service.create_page(payload)
    page_id = response['id']

    Activity.create(
      recording_id: recording.id,
      page_id: page_id,
      page_url: notion_service.construct_notion_url(page_id),
      action: 'created',
      database_id: ENV.fetch("TASKS_DB_KEY"),
      database_name: 'tasks',
      status: 'completed'
    )
  end

  def process_recommendation_transcription(openai_service, notion_service, note)
    recommendation = openai_service.extract_recommendation_summary(message: note)
    recommendation_type = openai_service.extract_recommendation_type(message: note)
    people_entities = openai_service.extract_related_entities(message: note, default: false) || []

    Rails.logger.debug "Recommendation: #{recommendation}, type: #{recommendation_type}, people: #{people_entities}"
    recording = Recording.create(
      body: note,
      summary: recommendation,
      recording_type: 'recommendation',
      status: 'complete'
    )

    properties_hash = {
      'Name' => { type: 'title', value: recommendation }
    }

    # Process people_entities to assign authors and recommenders
    people_entities.each do |entity|
      page_id, match_type = notion_service.find_or_create_entity(
        name: entity['name'],
        database_key: :people
      )
      # Map 'author' and 'recommender' to the correct fields
      relation_name = case entity['type']
                      when 'recommender' then 'People'   # Field for recommenders
                      when 'author' then 'Authors'      # Field for authors
                      else nil
                      end
      next unless relation_name

      properties_hash[relation_name] ||= { type: 'relation', value: [] }
      properties_hash[relation_name][:value] << page_id
    end

    properties = notion_service.construct_properties(properties_hash)

    payload = {
      parent: { database_id: NotionService::DATABASES[:recommendations] },
      properties: properties
    }

    response = notion_service.create_page(payload)
    page_id = response['id']

    Activity.create(
      recording_id: recording.id,
      page_id: page_id,
      page_url: notion_service.construct_notion_url(page_id),
      action: 'created',
      database_id: ENV.fetch("RECOMMENDATIONS_DB_KEY"),
      database_name: 'recommendations',
      status: 'completed'
    )
  end

  def process_ingredient_transcription(openai_service, notion_service, note)
    Rails.logger.debug "Transcription: #{note}"
    ingredients = openai_service.extract_ingredients(message: note) || []
    Rails.logger.debug "Ingredients: #{ingredients}"

    recording = Recording.create(
      body: note,
      summary: 'Update to shopping list.',
      recording_type: 'ingredient',
      status: 'complete'
    )

    update_values = lambda do |page, item|
      current_amount = notion_service.get_property_value(
        page: page,
        property_name: 'Amount Needed'
      ) || 0
      new_amount = current_amount + item['quantity'].to_i
      Rails.logger.debug "#{item['name']} will be adjusted from #{current_amount} to #{new_amount}"
      { 'Amount Needed' => { type: 'number', value: new_amount } }
    end

    Rails.logger.debug "update_values lambda defined: #{update_values}"

    # Pass allow_creation: false to prevent page creation
    notion_service.update_items(:ingredients, ingredients, update_values, allow_creation: false)
  end

  def process_recipe_transcription(openai_service, notion_service, note)
    recipes = openai_service.extract_recipes(message: note) || []
    Rails.logger.debug("#{note}: , #{recipes}")

    update_values = lambda do |_page, _item|
      { 'Planned' => { type: 'checkbox', value: true } }
    end

    Rails.logger.debug("Update Values hash: #{update_values}")

    notion_service.update_items(:recipes, recipes, update_values)
  end

  def process_wordle_transcription(openai_service, notion_service, note)
    scores = openai_service.extract_wordle_scores(message: note)
    Rails.logger.debug "Extracted scores: #{scores}"
  
    if scores['Mark'].nil? || scores['Lorna'].nil?
      Rails.logger.error "Could not extract scores for both Mark and Lorna."
      return
    end
  
    recording = Recording.create(
      body: note,
      summary: "Wordle scores updated",
      recording_type: 'wordle',
      status: 'complete'
    )
  
    database_id = NotionService::DATABASES[:wordle_games]
    today_date = Date.today.strftime('%Y-%m-%d')
    filter = {
      property: 'Date',
      date: { equals: today_date }
    }
  
    Rails.logger.debug "Searching for Wordle game on date: #{today_date}"
  
    response = notion_service.client.database_query(
      database_id: database_id,
      filter: filter
    )
  
    if response && response['results'] && !response['results'].empty?
      page = response['results'].first
      page_id = page['id']
      Rails.logger.debug "Found Wordle game page: #{page_id}"
  
      properties = notion_service.construct_properties(
        {
          "Mark's Score" => { type: 'number', value: scores['Mark'].to_i },
          "Lorna's Score" => { type: 'number', value: scores['Lorna'].to_i }
        }
      )
  
      notion_service.update_page(page_id, properties: properties)
  
      Activity.create(
        recording_id: recording.id,
        page_id: page_id,
        page_url: notion_service.construct_notion_url(page_id),
        action: 'updated',
        database_id: database_id,
        database_name: 'wordle_games',
        status: 'completed'
      )
  
      notion_service.action_log << { message: "Updated Wordle scores for #{today_date}", url: notion_service.construct_notion_url(page_id) }
    else
      Rails.logger.error "No Wordle game found for date #{today_date}"
      notion_service.action_log << { message: "No Wordle game found for date #{today_date}", url: nil }
    end
  end

  def process_restaurant_transcription(openai_service, notion_service, note)
    info = openai_service.extract_restaurant_info(message: note)
    Rails.logger.debug "Extracted restaurant info: #{info}"
  
    restaurant_name = info['restaurant_name']
    recommender_name = info['recommender_name'] || 'Mark'
  
    page_id, _ = notion_service.find_or_create_entity(
      name: restaurant_name,
      database_key: :restaurants,
      allow_creation: true
    )
  
    if page_id.nil?
      Rails.logger.error "Failed to find or create restaurant: #{restaurant_name}"
      return
    end
  
    recommender_page_id, _ = notion_service.find_or_create_entity(
      name: recommender_name,
      database_key: :people,
      allow_creation: true
    )
  
    page = notion_service.client.page(page_id: page_id)
    existing_recommenders = notion_service.get_property_value(page: page, property_name: 'Recommenders') || []
  
    recommenders = existing_recommenders + [recommender_page_id]
    recommenders.uniq!
  
    properties = notion_service.construct_properties(
      {
        'Recommenders' => { type: 'relation', value: recommenders }
      }
    )
  
    notion_service.update_page(page_id, properties: properties)
  
    recording = Recording.create(
      body: note,
      summary: "Restaurant recommendation: #{restaurant_name}",
      recording_type: 'restaurant',
      status: 'complete'
    )
  
    Activity.create(
      recording_id: recording.id,
      page_id: page_id,
      page_url: notion_service.construct_notion_url(page_id),
      action: 'updated',
      database_id: NotionService::DATABASES[:restaurants],
      database_name: 'restaurants',
      status: 'completed'
    )
  
    notion_service.action_log << { message: "Processed restaurant recommendation for '#{restaurant_name}'", url: notion_service.construct_notion_url(page_id) }
  end

  def process_idea_transcription(openai_service, notion_service, note)
    idea = openai_service.extract_idea_title_and_body(message: note)
    Rails.logger.debug "Extracted idea: #{idea}"
  
    title = idea['title']
    body = idea['body']
  
    properties_hash = {
      'Name' => { type: 'title', value: title }
    }

    Rails.logger.debug "#{title}: #{body}"

    Rails.logger.debug "Properties_hash:\n#{properties_hash}}"

    properties = notion_service.construct_properties(properties_hash)

    Rails.logger.debug "Properties:\n#{properties_hash}}"
    children = [
      {
        object: 'block',
        type: 'paragraph',
        paragraph: {
          rich_text: [
            {
              type: 'text',
              text: {
                'content' => body
              }
            }
          ]
        }
      }
    ]
  
    payload = {
      parent: { database_id: NotionService::DATABASES[:ideas] },
      properties: properties,
      children: children
    }
    Rails.logger.debug "Final payload: \n#{payload}"
    response = notion_service.create_page(payload)
    Rails.logger.debug "Response: #{response}"
    page_id = response['id']
    Rails.logger.debug "Page ID: #{page_id}"
  
    recording = Recording.create(
      body: note,
      summary: title,
      recording_type: 'idea',
      status: 'complete'
    )
  
    Activity.create(
      recording_id: recording.id,
      page_id: page_id,
      page_url: notion_service.construct_notion_url(page_id),
      action: 'created',
      database_id: NotionService::DATABASES[:ideas],
      database_name: 'ideas',
      status: 'completed'
    )
  
    notion_service.action_log << { message: "Added new idea '#{title}'", url: notion_service.construct_notion_url(page_id) }
  end  
end
