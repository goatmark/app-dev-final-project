# app/controllers/main_controller.rb
class MainController < ApplicationController
  protect_from_forgery except: :upload_audio

  def main
    render(template: "main_templates/home")
  end

  def submit
    @note = params.fetch("input", "")
    @hardcore_mode = params[:hardcore_mode] == '1'
    flash[:note] = @note
    flash[:hardcore_mode] = @hardcore_mode
    redirect_to("/processing")
  end

  def processing
    @note = flash[:note]
    @hardcore_mode = flash[:hardcore_mode]
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

    if @hardcore_mode
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
    hardcore_mode = params[:hardcore_mode] == '1'

    if audio_file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      FileUtils.mkdir_p(File.dirname(temp_audio_path))
      File.open(temp_audio_path, 'wb') do |file|
        file.write(audio_file.read)
      end

      openai_class = OpenaiService.new
      transcription = openai_class.transcribe_audio(temp_audio_path.to_s)

      File.delete(temp_audio_path) if File.exist?(temp_audio_path)

      if hardcore_mode
        # Process the transcription and update Notion directly
        @note = transcription
        @todays_date = Date.today.strftime("%Y-%m-%d")
        @result = openai_class.prompt_classify(message: @note)

        if @result == "note"
          @body = openai_class.prompt_note_summary(message: @note)
          @title = openai_class.prompt_note_title(message: @note)
          notion_class = NotionService.new
          notion_class.add_note(@title, @body, @todays_date)
          flash[:notice] = "Added \"#{@title}\" to Notes, with body: \"#{@body}\""
        elsif @result == "task"
          @task = openai_class.prompt_extract_task(message: @note)
          @deadline = openai_class.prompt_extract_deadline(message: @note)
          @action_date = openai_class.prompt_extract_action_date(message: @note)
          notion_class = NotionService.new
          notion_class.add_task(@task, @deadline, @action_date)
          flash[:notice] = "Added \"#{@task}\" to Tasks, due \"#{@deadline}\", action date \"#{@action_date}\""
        else
          flash[:alert] = "Could not classify the transcription."
          render json: { success: false, error: "Could not classify the transcription." }
          return
        end

        render json: { success: true }
      else
        # Non-hardcore mode: return transcription for manual submission
        render json: { transcription: transcription }
      end
    else
      render json: { error: 'No audio file received.' }, status: :unprocessable_entity
    end
  end
end
