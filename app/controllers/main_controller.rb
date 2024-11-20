# app / controllers / main_controller.rb
class MainController < ApplicationController

  protect_from_forgery except: :upload_audio

  def main
    render({:template => "main_templates/home"})
  end 

  def submit
    @note = params.fetch("input", "")
    flash[:note] = @note
    
    redirect_to("/processing")
  end

  def processing
    @note = flash[:note]

    @todays_date = Date.today
    @todays_date = @todays_date.strftime("%Y-%m-%d")
    flash[:todays_date] = @todays_date
    
    openai_class = OpenaiService.new

    @result = openai_class.prompt_classify(message: @note)
    flash[:result] = @result

    if @result == "note"
      @body = openai_class.prompt_note_summary(message: @note)
      @title = openai_class.prompt_note_title(message: @note)
      flash[:body] = @body
      flash[:title] = @title
    elsif @result == "task"
      @task = openai_class.prompt_extract_task(message: @note)
      @action_date = openai_class.prompt_extract_action_date(message: @note)
      @deadline = openai_class.prompt_extract_deadline(message: @note)
      flash[:task] = @task
      flash[:deadline] = @deadline
      flash[:action_date] = @action_date
    else
    end

    render({:template => "main_templates/processing"})
  end

  def confirm

    @result = flash[:result]
    notion_class = NotionService.new
    
    @todays_date = flash[:todays_date]

    if @result == "note"
      @body = flash[:body]
      @title = flash[:title]
      notion_class.add_note(@title, @body, @todays_date)
    elsif @result == "task"
      @task = flash[:task]
      @deadline = flash[:deadline]
      @action_date = flash[:action_date]
      notion_class.add_task(@task, @deadline, @action_date)
    else
    end


    redirect_to("/")
  end

  def upload_audio
    audio_file = params[:audio_file]

    if audio_file
      temp_audio_path = Rails.root.join('tmp', 'uploads', audio_file.original_filename)
      FileUtils.mkdir_p(File.dirname(temp_audio_path))
      File.open(temp_audio_path, 'wb') do |file|
        file.write(audio_file.read)
      end

      openai_class = OpenaiService.new
      transcription = openai_class.transcribe_audio(temp_audio_path.to_s)

      File.delete(temp_audio_path) if File.exist?(temp_audio_path)

      render json: { transcription: transcription }
    else
      render json: { error: 'No audio file received.' }, status: :unprocessable_entity
    end
  end
end
