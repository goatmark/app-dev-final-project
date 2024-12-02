class ActivitiesController < ApplicationController
  def index
    matching_activities = Activity.all

    @list_of_activities = matching_activities.order({ :created_at => :desc })

    render({ :template => "activities/index" })
  end

  def show
    the_id = params.fetch("path_id")

    matching_activities = Activity.where({ :id => the_id })

    @the_activity = matching_activities.at(0)

    render({ :template => "activities/show" })
  end

  def create
    the_activity = Activity.new
    the_activity.action_type = params.fetch("query_action_type")
    the_activity.recording_id = params.fetch("query_recording_id")
    the_activity.page_id = params.fetch("query_page_id")
    the_activity.database_id = params.fetch("query_database_id")
    the_activity.action = params.fetch("query_action")
    the_activity.page_url = params.fetch("query_page_url")

    if the_activity.valid?
      the_activity.save
      redirect_to("/activities", { :notice => "Activity created successfully." })
    else
      redirect_to("/activities", { :alert => the_activity.errors.full_messages.to_sentence })
    end
  end

  def update
    the_id = params.fetch("path_id")
    the_activity = Activity.where({ :id => the_id }).at(0)

    the_activity.action_type = params.fetch("query_action_type")
    the_activity.recording_id = params.fetch("query_recording_id")
    the_activity.page_id = params.fetch("query_page_id")
    the_activity.database_id = params.fetch("query_database_id")
    the_activity.action = params.fetch("query_action")
    the_activity.page_url = params.fetch("query_page_url")

    if the_activity.valid?
      the_activity.save
      redirect_to("/activities/#{the_activity.id}", { :notice => "Activity updated successfully."} )
    else
      redirect_to("/activities/#{the_activity.id}", { :alert => the_activity.errors.full_messages.to_sentence })
    end
  end

  def destroy
    the_id = params.fetch("path_id")
    the_activity = Activity.where({ :id => the_id }).at(0)

    the_activity.destroy

    redirect_to("/activities", { :notice => "Activity deleted successfully."} )
  end
end
