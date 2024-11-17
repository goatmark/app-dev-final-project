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

    @chosen_prompt = @note

    @suppress_api_calls = true
    
    if @suppress_api_calls
      @result = "API calls disabled, #{@note}"
    else
      openai_class = OpenaiService.new

      @result = openai_class.prompt_classify(message: @chosen_prompt)

      if @result == "note"
        @body = openai_class.prompt_note_summary(message: @chosen_prompt)
        @title = openai_class.prompt_note_title(message: @chosen_prompt)
        notion_class = NotionService.new
        @todays_date = Date.today
        @todays_date = @todays_date.strftime("%Y-%m-%d")
        notion_class.add_note(@title, @body, @todays_date)
      elsif @result == "task"
        @task = openai_class.prompt_extract_task(message: @chosen_prompt)
        @deadline = openai_class.prompt_extract_deadline(message: @chosen_prompt)
      else
      end
    end
    

    render({:template => "main_templates/processing"})
  end
end
