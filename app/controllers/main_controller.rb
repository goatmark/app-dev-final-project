# app/controllers/main_controller.rb

class MainController < ApplicationController
  protect_from_forgery except: :upload_audio

  def main
    @action_log = flash[:notice] || ""
    render(template: "main_templates/home")
  end

  def submit
    @note = params.fetch("input", "")
    @skip_confirmation = params[:skip_confirmation] == '1'
    redirect_to("/processing", flash: { note: @note, skip_confirmation: @skip_confirmation })
  end

  def processing
    @note = flash[:note]
    @skip_confirmation = flash[:skip_confirmation]
    @todays_date = Date.today.strftime("%Y-%m-%d")

    openai_service = OpenaiService.new
    @result = openai_service.classify_message(message: @note)

    case @result
    when "note"
      process_note
    when "task"
      process_task
    when "ingredient"
      process_ingredients
    when "recipe"
      process_recipes
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
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    when "task"
      @task = params[:task]
      @deadline = params[:deadline]
      @action_date = params[:action_date]
      @related_entities = params[:related_entities].present? ? JSON.parse(params[:related_entities]) : []
      create_task_in_notion(notion_service)
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    when "ingredient"
      @ingredients = params[:ingredients].present? ? JSON.parse(params[:ingredients]) : []
      notion_service.update_ingredients(@ingredients)
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    when "recipe"
      @recipes = params[:recipes].present? ? JSON.parse(params[:recipes]) : []
      notion_service.update_recipes(@recipes)
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    else
      flash[:alert] = "Unknown result type."
      redirect_to "/"
    end
  end

  def upload_audio
    audio_file = params[:audio_file]
    skip_confirmation = params[:skip_confirmation] == '1'

    if audio_file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      FileUtils.mkdir_p(File.dirname(temp_audio_path))
      File.open(temp_audio_path, 'wb') { |file| file.write(audio_file.read) }

      openai_service = OpenaiService.new
      transcription = openai_service.transcribe_audio(audio_file_path: temp_audio_path.to_s)

      File.delete(temp_audio_path) if File.exist?(temp_audio_path)

      if skip_confirmation
        # Process transcription and update Notion directly
        result = process_transcription(transcription)
        if result[:success]
          flash[:notice] = result[:message]
          render json: { success: true }
        else
          flash[:alert] = result[:error]
          render json: { success: false, error: result[:error] }
        end
      else
        # Non-confirmation mode: return transcription for manual submission
        render json: { transcription: transcription }
      end
    else
      render json: { error: 'No audio file received.' }, status: :unprocessable_entity
    end
  end

  private

  def process_note
    openai_service = OpenaiService.new
    notion_service = NotionService.new

    @body = openai_service.extract_note_body(message: @note)
    @title = openai_service.extract_note_title(message: @note)
    @related_entities = openai_service.extract_related_entities(message: @note) || []
    @api_response = openai_service.get_last_api_response

    process_entities(notion_service, nil, 'note')

    if @skip_confirmation
      create_note_in_notion(notion_service)
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def process_task
    openai_service = OpenaiService.new
    notion_service = NotionService.new

    @task = openai_service.extract_task_summary(message: @note)
    @deadline = openai_service.extract_deadline(message: @note)
    @action_date = openai_service.extract_action_date(message: @note)
    @related_entities = openai_service.extract_related_entities(message: @note) || []
    @api_response = openai_service.get_last_api_response

    process_entities(notion_service, nil, 'task')

    if @skip_confirmation
      create_task_in_notion(notion_service)
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def process_ingredients
    openai_service = OpenaiService.new
    notion_service = NotionService.new

    @ingredients = openai_service.extract_ingredients(message: @note) || []
    @api_response = openai_service.get_last_api_response

    # Process ingredients to update quantities and get matching info
    notion_service.update_ingredients(@ingredients)

    if @skip_confirmation
      flash[:notice] = notion_service.action_log.join("\n")
      redirect_to "/"
    else
      render template: "main_templates/processing"
    end
  end

  def process_recipes
    openai_service = OpenaiService.new
    notion_service = NotionService.new

    @recipes = openai_service.extract_recipes(message: @note) || []
    @api_response = openai_service.get_last_api_response

    # Process recipes to mark as planned and get matching info
    notion_service.update_recipes(@recipes)

    if @skip_confirmation
      flash[:notice] = notion_service.action_log.join("\n")
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
  end

  def process_transcription(transcription)
    openai_service = OpenaiService.new
    @note = transcription
    @todays_date = Date.today.strftime("%Y-%m-%d")
    @result = openai_service.classify_message(message: @note)

    notion_service = NotionService.new

    case @result
    when "note"
      @body = openai_service.extract_note_body(message: @note)
      @title = openai_service.extract_note_title(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      create_note_in_notion(notion_service)
      message = notion_service.action_log.join("\n")
      { success: true, message: message }
    when "task"
      @task = openai_service.extract_task_summary(message: @note)
      @deadline = openai_service.extract_deadline(message: @note)
      @action_date = openai_service.extract_action_date(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      create_task_in_notion(notion_service)
      message = notion_service.action_log.join("\n")
      { success: true, message: message }
    when "ingredient"
      @ingredients = openai_service.extract_ingredients(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      notion_service.update_ingredients(@ingredients)
      flash[:notice] = notion_service.action_log.join("\n")
      { success: true, message: notion_service.action_log.join("\n") }
    when "recipe"
      @recipes = openai_service.extract_recipes(message: @note)
      @related_entities = openai_service.extract_related_entities(message: @note)
      notion_service.update_recipes(@recipes)
      flash[:notice] = notion_service.action_log.join("\n")
      { success: true, message: notion_service.action_log.join("\n") }
    else
      { success: false, error: 'Could not classify the transcription.' }
    end
  rescue => e
    Rails.logger.error "Processing transcription failed: #{e.message}"
    { success: false, error: 'An error occurred during processing.' }
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
    else
      nil
    end
  end
end
