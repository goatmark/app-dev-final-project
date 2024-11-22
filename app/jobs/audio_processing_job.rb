# app/jobs/audio_processing_job.rb

class AudioProcessingJob < ApplicationJob
  queue_as :default

  def perform(audio_file_path, skip_confirmation)
    openai_class = OpenaiService.new
    transcription = openai_class.transcribe_audio(audio_file_path)

    # Delete the temporary file
    File.delete(audio_file_path) if File.exist?(audio_file_path)

    # Process the transcription
    process_transcription(transcription, skip_confirmation)
  rescue => e
    Rails.logger.error "AudioProcessingJob failed: #{e.message}"
    # Optionally notify via email or error tracking service
  end

  private

  def process_transcription(transcription, skip_confirmation)
    openai_class = OpenaiService.new
    note = transcription
    todays_date = Date.today.strftime("%Y-%m-%d")
    result = openai_class.prompt_classify(message: note)

    if result == "note"
      body = openai_class.prompt_note_summary(message: note)
      title = openai_class.prompt_note_title(message: note)
      notion_class = NotionService.new
      notion_class.add_note(title, body, todays_date)
      # Log success or handle accordingly
    elsif result == "task"
      task = openai_class.prompt_extract_task(message: note)
      deadline = openai_class.prompt_extract_deadline(message: note)
      action_date = openai_class.prompt_extract_action_date(message: note)
      notion_class = NotionService.new
      notion_class.add_task(task, deadline, action_date)
      # Log success or handle accordingly
    else
      Rails.logger.error "Could not classify the transcription."
      # Handle classification failure
    end
  end
end
