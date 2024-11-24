class MainController < ApplicationController
  protect_from_forgery except: :upload_audio

  def main
    @action_log = flash[:notice] || ""
    render(template: "main_templates/home")
  end

  def submit
    @note = params.fetch("input", "")
    @skip_confirmation = params[:skip_confirmation] == '1'
    flash[:note] = @note
    flash[:skip_confirmation] = @skip_confirmation
    redirect_to("/processing")
  end

  def processing
    @note = flash[:note]
    @skip_confirmation = flash[:skip_confirmation]
    @todays_date = Date.today.strftime("%Y-%m-%d")

    openai_class = OpenaiService.new
    @result = openai_class.prompt_classify(message: @note)

    notion_class = NotionService.new

    case @result
    when "note"
      @body = openai_class.prompt_note_summary(message: @note)
      @title = openai_class.prompt_note_title(message: @note)

      # Extract related entities
      @related_entities = openai_class.extract_related_entities(message: @note)

      if @skip_confirmation
        process_note(notion_class, openai_class)
        flash[:notice] = notion_class.action_log.join("\n")
        redirect_to "/"
      else
        flash[:body] = @body
        flash[:title] = @title
        flash[:result] = @result
        flash[:related_entities] = @related_entities
        render template: "main_templates/processing"
      end
    when "task"
      @task = openai_class.prompt_extract_task(message: @note)
      @deadline = openai_class.prompt_extract_deadline(message: @note)
      @action_date = openai_class.prompt_extract_action_date(message: @note)

      # Extract related entities
      @related_entities = openai_class.extract_related_entities(message: @note)

      if @skip_confirmation
        process_task(notion_class, openai_class)
        flash[:notice] = notion_class.action_log.join("\n")
        redirect_to "/"
      else
        flash[:task] = @task
        flash[:deadline] = @deadline
        flash[:action_date] = @action_date
        flash[:result] = @result
        flash[:related_entities] = @related_entities
        render template: "main_templates/processing"
      end
    else
      redirect_to "/", alert: "Could not classify the transcription."
    end
  end

  def confirm
    @result = flash[:result]
    @todays_date = Date.today.strftime("%Y-%m-%d")

    openai_class = OpenaiService.new
    notion_class = NotionService.new

    case @result
    when "note"
      @body = flash[:body]
      @title = flash[:title]
      @related_entities = flash[:related_entities] || []

      process_note(notion_class, openai_class)
      flash[:notice] = notion_class.action_log.join("\n")
      redirect_to "/"
    when "task"
      @task = flash[:task]
      @deadline = flash[:deadline]
      @action_date = flash[:action_date]
      @related_entities = flash[:related_entities] || []

      process_task(notion_class, openai_class)
      flash[:notice] = notion_class.action_log.join("\n")
      redirect_to "/"
    else
      flash[:alert] = "Unknown result type."
      redirect_to "/"
    end
  end

  # Place upload_audio here, as a public method
  def upload_audio
    audio_file = params[:audio_file]
    skip_confirmation = params[:skip_confirmation] == '1'

    if audio_file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      FileUtils.mkdir_p(File.dirname(temp_audio_path))
      File.open(temp_audio_path, 'wb') { |file| file.write(audio_file.read) }

      openai_class = OpenaiService.new
      transcription = openai_class.transcribe_audio(audio_file_path: temp_audio_path.to_s)

      File.delete(temp_audio_path) if File.exist?(temp_audio_path)

      if skip_confirmation
        # Process transcription and update Notion directly
        result = process_transcription(note: transcription)
        if result[:success]
          flash[:notice] = result[:message]
          render json: { success: true }
        else
          flash[:alert] = result[:error]
          render json: { success: false, error: result[:error] }
        end
      else
        # Non-hardcore mode: return transcription for manual submission
        render json: { transcription: transcription }
      end
    else
      render json: { error: 'No audio file received.' }, status: :unprocessable_entity
    end
  end

  private

  def process_note(notion_class, openai_class)
    # Create the note
    new_note = notion_class.add_note(title: @title, body: @body, formatted_date: @todays_date)

    # Process entities and add relations independently
    relations_hash = {}
    @related_entities.each do |entity|
      page_id = notion_class.find_or_create_entity(name: entity['name'], type: entity['type'])
      relation_field = get_relation_field_for_note_entity_type(entity['type'])
      if relation_field && page_id
        relations_hash[relation_field] ||= []
        relations_hash[relation_field] << page_id
      end
    end

    # Add relations to the note
    if relations_hash.any?
      notion_class.add_relations_to_page(page_id: new_note['id'], relations_hash: relations_hash, relation_fields: NotionService::NOTES_RELATIONS)
    end
  end

  def process_task(notion_class, openai_class)
    # Create the task
    new_task = notion_class.add_task(task_name: @task, due_date: @deadline, action_date: @action_date)

    # Process entities and add relations independently
    relations_hash = {}
    @related_entities.each do |entity|
      page_id = notion_class.find_or_create_entity(name: entity['name'], type: entity['type'])
      relation_field = get_relation_field_for_task_entity_type(entity['type'])
      if relation_field && page_id
        relations_hash[relation_field] ||= []
        relations_hash[relation_field] << page_id
      end
    end

    # Add relations to the task
    if relations_hash.any?
      notion_class.add_relations_to_page(page_id: new_task['id'], relations_hash: relations_hash, relation_fields: NotionService::TASKS_RELATIONS)
    end
  end

  def process_transcription(note:)
    openai_class = OpenaiService.new
    todays_date = Date.today.strftime("%Y-%m-%d")
    result = openai_class.prompt_classify(message: note)

    notion_class = NotionService.new

    case result
    when "note"
      body = openai_class.prompt_note_summary(message: note)
      title = openai_class.prompt_note_title(message: note)
      @title = title
      @body = body
      @related_entities = openai_class.extract_related_entities(message: note)
      process_note(notion_class, openai_class)
      message = notion_class.action_log.join("\n")
      { success: true, message: message }
    when "task"
      task = openai_class.prompt_extract_task(message: note)
      deadline = openai_class.prompt_extract_deadline(message: note)
      action_date = openai_class.prompt_extract_action_date(message: note)
      @task = task
      @deadline = deadline
      @action_date = action_date
      @related_entities = openai_class.extract_related_entities(message: note)
      process_task(notion_class, openai_class)
      message = notion_class.action_log.join("\n")
      { success: true, message: message }
    else
      { success: false, error: 'Could not classify the transcription.' }
    end
  rescue => e
    Rails.logger.error "Processing transcription failed: #{e.message}"
    { success: false, error: 'An error occurred during processing.' }
  end

  def get_relation_field_for_note_entity_type(entity_type)
    case entity_type
    when 'person'
      'People'
    when 'company'
      'Company'
    when 'class'
      'Course'
    else
      nil
    end
  end

  def get_relation_field_for_task_entity_type(entity_type)
    case entity_type
    when 'person'
      'People'
    when 'company'
      'Organization'
    else
      nil
    end
  end
end
