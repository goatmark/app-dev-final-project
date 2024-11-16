# app / controllers / main_controller.rb
class MainController < ApplicationController

  def main
    render({:template => "main_templates/home"})
  end 

  def submit

    @note = params.fetch("input", "")
    
    redirect_to("/processing")
  end

  def processing
    prompt_1 = "On Tuesday, I need to pick up my dry cleaning."
    prompt_2 = "I have an assignment for my Digital Marketing Lab class due on Saturday."
    prompt_3 = "Make a note that I spoke with Alley yesterday. We discussed politics, music, and art."
    prompt_4 = "I need to go to the banquet next month."
    prompt_5 = "AYO GPT - can you help a m*f* remember that he's gotta fill up a m*f* car with some m*f* gas by Monday?"
    prompt_6 = "I had a long conversation with my Samuel yesterday. I told him my view of the world - that it's in decay, that we're about to face hard times, and that he shouldn't be too picky in choosing a job. It was a harsh but fair conversation."
    prompt_7 = "I can't believe it. I'm so screwed. I have 10 minutes to do the readings for my Digital Marketing Lab class and I haven't started. I'm so screwed. Oh my god oh my god oh my god. I have 10 minutes to read the entire Google Analytics 4 documentation and get a certification. I'm so screwed HELP ME."

    @chosen_prompt = prompt_7

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

    render({:template => "main_templates/processing"})
  end
end
