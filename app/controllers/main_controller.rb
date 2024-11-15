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
    prompt_3 = "I need to send a follow up email to Jessica about the cannabis club."
    prompt_4 = "I need to go to the banquet next month."
    prompt_5 = "AYO GPT - can you help a m*f* remember that he's gotta fill up a m*f* car with some m*f* gas by Monday?"

    @chosen_prompt = prompt_5

    openai_class = OpenaiService.new

    @result = openai_class.prompt_classify(message: @chosen_prompt)

    if @result == "note"
      @body = openai_class.prompt_note_summary(message: @chosen_prompt)
    elsif @result == "task"
      @task = openai_class.prompt_extract_task(message: @chosen_prompt)
      @deadline = openai_class.prompt_extract_deadline(message: @chosen_prompt)
    else
    end
    
    render({:template => "main_templates/processing"})
  end
end
