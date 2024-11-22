# app/controllers/main_controller.rb
class MainController < ApplicationController
  protect_from_forgery except: :upload_audio

  def main
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

    if @result == "note"
      @body = openai_class.prompt_note_summary(message: @note)
      @title = openai_class.prompt_note_title(message: @note)
    elsif @result == "task"
      @task = openai_class.prompt_extract_task(message: @note)
      @deadline = openai_class.prompt_extract_deadline(message: @note)
      @action_date = openai_class.prompt_extract_action_date(message: @note)
    else
      redirect_to "/", alert: "Could not classify the transcription."
      return
    end

    if @skip_confirmation
      notion_class = NotionService.new

      if @result == "note"
        notion_class.add_note(@title, @body, @todays_date)
        flash[:notice] = "Added \"#{@title}\" to Notes, with body: \"#{@body}\""
      elsif @result == "task"
        notion_class.add_task(@task, @deadline, @action_date)
        flash[:notice] = "Added \"#{@task}\" to Tasks, due \"#{@deadline}\", action date \"#{@action_date}\""
      end

      redirect_to "/"
    else
      flash[:result] = @result
      flash[:todays_date] = @todays_date

      if @result == "note"
        flash[:body] = @body
        flash[:title] = @title
      elsif @result == "task"
        flash[:task] = @task
        flash[:deadline] = @deadline
        flash[:action_date] = @action_date
      end

      render template: "main_templates/processing"
    end
  end

  def confirm
    @result = flash[:result]
    notion_class = NotionService.new
    @todays_date = flash[:todays_date]

    if @result == "note"
      @body = flash[:body]
      @title = flash[:title]
      notion_class.add_note(@title, @body, @todays_date)
      flash[:notice] = "Added \"#{@title}\" to Notes, with body: \"#{@body}\""
    elsif @result == "task"
      @task = flash[:task]
      @deadline = flash[:deadline]
      @action_date = flash[:action_date]
      notion_class.add_task(@task, @deadline, @action_date)
      flash[:notice] = "Added \"#{@task}\" to Tasks, due \"#{@deadline}\", action date \"#{@action_date}\""
    end

    redirect_to "/"
  end

  def upload_audio
    audio_file = params[:audio_file]
    skip_confirmation = params[:skip_confirmation] == '1'
  
    if audio_file
      # Save the uploaded file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      FileUtils.mkdir_p(File.dirname(temp_audio_path))
      File.open(temp_audio_path, 'wb') { |file| file.write(audio_file.read) }
  
      # Enqueue the processing job
      AudioProcessingJob.perform_later(temp_audio_path.to_s, skip_confirmation)
  
      render json: { success: true, message: 'Your dictation is being processed.' }
    else
      render json: { error: 'No audio file received.' }, status: :unprocessable_entity
    end
  end
end
