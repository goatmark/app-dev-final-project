class MainController < ApplicationController
  protect_from_forgery except: :upload_audio

  def main
    @action_log = flash[:notice] || []
    @transcription = flash[:transcription] || ""
    @skip_confirmation = flash[:skip_confirmation] == '1'
    render(template: "main_templates/home")
  end

  def submit
    @note = params.fetch("input", "")
    skip_confirmation = (params.fetch("skip_confirmation", false) || flash[:skip_confirmation])
    redirect_to("/processing", flash: { note: @note, skip_confirmation: skip_confirmation })
  end

  def processing
    @note = flash[:note]
    skip_confirmation = flash[:skip_confirmation]
    @todays_date = Date.today.strftime("%Y-%m-%d")

    openai_service = OpenaiService.new
    notion_service = NotionService.new
    @result = openai_service.classify_message(message: @note)

    case @result
    when "note"
      process_note(notion_service)
    when "task"
      process_task(notion_service)
    when "ingredient"
      process_ingredients(notion_service)
    when "recipe"
      process_recipes(notion_service)
    when "recommendation"
      process_recommendation(notion_service)
    when "idea"
      # tbd
    else
      redirect_to "/", alert: "Could not classify the transcription."
    end
  end

  def confirm
    @result = params[:result]
    notion_service = NotionService.new

    case @result
    when "note"
      @title = params[:title]
      @body = params[:body]
      @date = params[:todays_date]
      @related_entities = params[:related_entities].present? ? JSON.parse(params[:related_entities]) : []
      create_note_in_notion(notion_service)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    when "task"
      @task = params[:task]
      @deadline = params[:deadline]
      @action_date = params[:action_date]
      @related_entities = params[:related_entities].present? ? JSON.parse(params[:related_entities]) : []
      create_task_in_notion(notion_service)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    when "recommendation"
      @recommendation = params[:recommendation]
      @recommendation_type = params[:recommendation_type]
      create_recommendation_in_notion(notion_service)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    when "ingredient"
      @ingredients = params[:ingredients].present? ? JSON.parse(params[:ingredients]) : []
      notion_service.update_ingredients(@ingredients)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    when "recipe"
      @recipes = params[:recipes].present? ? JSON.parse(params[:recipes]) : []
      notion_service.update_recipes(@recipes)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    else
      flash[:alert] = "Unknown result type."
      redirect_to "/"
    end
  end

  def upload_audio
    audio_file = params[:audio_file]
    skip_confirmation = params[:skip_confirmation] == '1'
    Rails.logger.debug "Received upload_audio request. Audio file present: #{audio_file.present?}, Skip Confirmation: #{skip_confirmation}"
  
    if audio_file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      Rails.logger.debug "Saving audio to: #{temp_audio_path}"
      begin
        FileUtils.mkdir_p(File.dirname(temp_audio_path))
        File.open(temp_audio_path, 'wb') { |file| file.write(audio_file.read) }
        Rails.logger.debug "Audio file saved successfully. Size: #{File.size(temp_audio_path)} bytes."
  
        # Check file size (e.g., minimum 1KB)
        if File.size(temp_audio_path) < 1000
          Rails.logger.error "Audio file too small: #{File.size(temp_audio_path)} bytes."
          File.delete(temp_audio_path)
          render json: { error: 'Audio file is too short. Please record a longer message.' }, status: :unprocessable_entity
          return
        end
  
        openai_service = OpenaiService.new
        transcription = openai_service.transcribe_audio(audio_file_path: temp_audio_path.to_s)
        Rails.logger.debug "Transcription received: #{transcription}"
  
        if skip_confirmation
          Rails.logger.debug "Processing transcription in hardcore mode."
          result = process_transcription(transcription)
          Rails.logger.debug "process_transcription() method complete."
  
          if result[:success]
            flash[:transcription] = transcription
            flash[:notice] = result[:action_log]
            render json: { success: true, action_log: result[:action_log], transcription: transcription }, status: :ok
          else
            render json: { success: false, error: result[:error] }, status: :unprocessable_entity
          end
        else
          Rails.logger.debug "Returning transcription for manual confirmation."
          render json: { transcription: transcription }, status: :ok
        end
      rescue => e
        Rails.logger.error "Exception in upload_audio: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: 'An error occurred while processing the audio.' }, status: :internal_server_error
      ensure
        if File.exist?(temp_audio_path)
          File.delete(temp_audio_path)
          Rails.logger.debug "Temporary audio file deleted."
        end
      end
    else
      Rails.logger.warn "No audio file received in upload_audio."
      render json: { error: 'No audio file received.' }, status: :unprocessable_entity
    end
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
      @body = openai_service.extract_note_body(message: @note)
      @title = openai_service.extract_note_title(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      Rails.logger.debug "Note metadata extracted."
      create_note_in_notion(notion_service)
    when "task"
      @task = openai_service.extract_task_summary(message: @note)
      @deadline = openai_service.extract_deadline(message: @note)
      @action_date = openai_service.extract_action_date(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      create_task_in_notion(notion_service)
    when "recommendation"
      @recommendation = openai_service.extract_recommendation_summary(message: @note)
      @recommendation_type = openai_service.extract_recommendation_type(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      create_recommendation_in_notion(notion_service)
    when "ingredient"
      @ingredients = openai_service.extract_ingredients(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      notion_service.update_ingredients(@ingredients)
    when "recipe"
      @recipes = openai_service.extract_recipes(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      notion_service.update_recipes(@recipes)
    else
      Rails.logger.error "Could not classify the transcription."
      return { success: false, error: 'Could not classify the transcription.' }
    end
  
    # Consolidate Action Log messages (array of hashes)
    action_log = notion_service.action_log
    Rails.logger.debug "Item processing complete."
    return { success: true, action_log: action_log }
  rescue => e
    Rails.logger.error "Processing transcription failed: #{e.message}"
    return { success: false, error: 'An error occurred during processing.' }
  end

  def process_note(notion_service)
    openai_service = OpenaiService.new

    Rails.logger.debug "Note. Body: #{@body}. Title: #{@title}."

    @body = openai_service.extract_note_body(message: @note)
    @title = openai_service.extract_note_title(message: @note)
    @related_entities = openai_service.extract_related_entities(message: @note) || []
    Rails.logger.debug "Note. Body: #{@body}. Title: #{@title}."
    Rails.logger.debug "Hardcore Mode? #{@skip_confirmation}"
    Rails.logger.debug "Starting entity processing."
    process_entities(notion_service, nil, 'note')

    if @skip_confirmation # hardcore mode turned on
      create_note_in_notion(notion_service)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to("/")
    else
      render template: "main_templates/processing"
    end
  end

  def process_task(notion_service)
    openai_service = OpenaiService.new

    @task = openai_service.extract_task_summary(message: @note)
    @deadline = openai_service.extract_deadline(message: @note)
    @action_date = openai_service.extract_action_date(message: @note)
    @related_entities = openai_service.extract_related_entities(message: @note) || []

    process_entities(notion_service, nil, 'task')

    if @skip_confirmation
      create_task_in_notion(notion_service)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def process_recommendation(notion_service)
    openai_service = OpenaiService.new

    @recommendation = openai_service.extract_recommendation_summary(message: @note)
    @recommendation_type = openai_service.extract_recommendation_type(message: @note)
    @related_entities = openai_service.extract_related_entities(message: @note) || []

    process_entities(notion_service, nil, 'recommendation')

    if @skip_confirmation
      create_recommendation_in_notion(notion_service)
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def process_ingredients(notion_service)
    openai_service = OpenaiService.new

    @ingredients = openai_service.extract_ingredients(message: @note) || []

    # Process ingredients to update quantities and get matching info
    notion_service.update_ingredients(@ingredients)

    if @skip_confirmation
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def process_recipes(notion_service)
    openai_service = OpenaiService.new

    @recipes = openai_service.extract_recipes(message: @note) || []

    # Process recipes to mark as planned and get matching info
    notion_service.update_recipes(@recipes)

    if @skip_confirmation
      flash[:notice] = notion_service.action_log
      flash[:transcription] = @note
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def create_note_in_notion(notion_service)
    new_note = notion_service.add_note(title: @title, body: @body, date: Date.today.strftime('%Y-%m-%d'), relations: @related_entities)
    process_entities(notion_service, new_note['id'], 'note')
  end

  def create_task_in_notion(notion_service)
    new_task = notion_service.add_task(task_name: @task, deadline: @deadline, action_date: @action_date, relations: @related_entities)
    process_entities(notion_service, new_task['id'], 'task')
  end

  def create_recommendation_in_notion(notion_service)
    new_recommendation = notion_service.add_recommendation(name: @recommendation, type: @recommendation_type, relations: @related_entities)
    process_entities(notion_service, new_recommendation['id'], 'recommendation')
  end

  def process_entities(notion_service, page_id, item_type)
    relations_hash = {}
    @related_entities.each do |entity|
      relation_field = get_relation_field_for_entity_type(entity['type'], item_type)
      next unless relation_field

      page_id_entity, match_type = notion_service.find_or_create_entity(name: entity['name'], relation_field: relation_field)
      relations_hash[relation_field] ||= []
      relations_hash[relation_field] << page_id_entity if page_id_entity

      entity['page_id'] = page_id_entity
      entity['match_type'] = match_type
    end

    if page_id && relations_hash.any?
      notion_service.add_relations_to_page(page_id: page_id, relations_hash: relations_hash, item_type: item_type)
    end

    return(relations_hash)
  end

  def get_relation_field_for_entity_type(entity_type, item_type)
    if item_type == 'note'
      {
        'person' => :people,
        'company' => :companies,
        'class' => :classes
      }[entity_type]
    elsif item_type == 'task'
      {
        'person' => :people,
        'company' => :companies,
        'class' => :classes
      }[entity_type]
    elsif item_type == 'ingredient'
      {
        'company' => :companies
      }[entity_type]
    elsif item_type == 'recipe'
      {
        'company' => :companies
      }[entity_type]
    elsif item_type == 'recommendation'
      {
        'person' => :people
      }[entity_type]
    else
      nil
    end
  end
end
