# app / controllers / main_controller.rb
class MainController < ApplicationController

  def main
    render({:template => "main_templates/home"})
  end 

  def submit
    audio_file = params[:audio_file]
  
    if audio_file.present?
      # Save the uploaded file temporarily
      file_path = Rails.root.join('tmp', audio_file.original_filename)
      File.open(file_path, 'wb') { |file| file.write(audio_file.read) }
  
      # Use the OpenAIService to transcribe the audio
      openai_service = OpenaiService.new
      transcription = openai_service.transcribe_audio(file_path)
  
      # Process the transcription as needed
      if transcription
        session[:transcription] = transcription
        redirect_to "/processing", notice: "Transcription successful!"
      else
        redirect_to "/", alert: "Transcription failed."
      end
  
      
    else
      redirect_to "/", alert: "No audio file uploaded."
    end
  end

  def processing
    transcription = session[:transcription]

    if transcription.blank?
      redirect_to "/", alert: "No transcription available."
      return
    end

    openai_class = OpenaiService.new

    @result = openai_class.prompt_classify(message: transcription)

    if @result == "note"
      @body = openai_class.prompt_note_summary(message: transcription)
      @title = openai_class.prompt_note_title(message: transcription)

      # Proceed to create Notion pages or further processing
      notion_class = NotionService.new
      @todays_date = Date.today.strftime("%Y-%m-%d")
      notion_class.add_note(@title, @body, @todays_date)
    elsif @result == "task"
      @task = openai_class.prompt_extract_task(message: transcription)
      @deadline = openai_class.prompt_extract_deadline(message: transcription)
    else
      redirect_to "/", alert: "Could not classify the transcription."
      return
    end

    # Clear the transcription from the session if you no longer need it
    session.delete(:transcription)

    render template: "main_templates/processing"
  end
end
