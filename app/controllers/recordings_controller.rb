# app / controllers / recordings_controller.rb

class RecordingsController < ApplicationController
  def index
    matching_recordings = Recording.all

    @list_of_recordings = matching_recordings.order({ :created_at => :desc })

    render({ :template => "recordings/index" })
  end

  def show
    the_id = params.fetch("path_id")

    matching_recordings = Recording.where({ :id => the_id })

    @the_recording = matching_recordings.at(0)

    render({ :template => "recordings/show" })
  end

  def create
    the_recording = Recording.new
    the_recording.recording_type = params.fetch("query_recording_type")
    the_recording.body = params.fetch("query_body")
    the_recording.summary = params.fetch("query_summary")
    the_recording.activities_count = params.fetch("query_activities_count")

    if the_recording.valid?
      the_recording.save
      redirect_to("/recordings", { :notice => "Recording created successfully." })
    else
      redirect_to("/recordings", { :alert => the_recording.errors.full_messages.to_sentence })
    end
  end

  def update
    the_id = params.fetch("path_id")
    the_recording = Recording.where({ :id => the_id }).at(0)

    the_recording.recording_type = params.fetch("query_recording_type")
    the_recording.body = params.fetch("query_body")
    the_recording.summary = params.fetch("query_summary")
    the_recording.activities_count = params.fetch("query_activities_count")

    if the_recording.valid?
      the_recording.save
      redirect_to("/recordings/#{the_recording.id}", { :notice => "Recording updated successfully."} )
    else
      redirect_to("/recordings/#{the_recording.id}", { :alert => the_recording.errors.full_messages.to_sentence })
    end
  end

  def destroy
    the_id = params.fetch("path_id")
    the_recording = Recording.where({ :id => the_id }).at(0)

    the_recording.destroy

    redirect_to("/recordings", { :notice => "Recording deleted successfully."} )
  end
end
