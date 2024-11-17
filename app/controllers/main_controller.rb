# app / controllers / main_controller.rb
class MainController < ApplicationController

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

    @suppress_api_calls = false

    @todays_date = Date.today
    @todays_date = @todays_date.strftime("%Y-%m-%d")
    flash[:todays_date] = @todays_date
    
    if @suppress_api_calls
      @result = "API calls disabled, #{@note}"
    else
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
        @deadline = openai_class.prompt_extract_deadline(message: @note)
        flash[:task] = @task
        flash[:deadline] = @deadline
      else
      end
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
      flash[:task] = @task
      flash[:deadline] = @deadline
    else
    end


    redirect_to("/")
  end
end
