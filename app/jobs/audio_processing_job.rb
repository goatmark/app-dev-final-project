# app/jobs/audio_processing_job.rb

class AudioProcessingJob < ApplicationJob
  queue_as :default

  def perform(audio_file_path, skip_confirmation)
    openai_class = OpenaiService.new
    transcription = openai_class.transcribe_audio(audio_file_path)

    # Delete the temporary file
    File.delete(audio_file_path) if File.exist?(audio_file_path)

    if skip_confirmation
      # Process and save directly to Notion
      # (Include your existing logic here)
    else
      # Save the transcription for user review or further processing
      # You might store it in the database or send a notification
    end
  end
end
