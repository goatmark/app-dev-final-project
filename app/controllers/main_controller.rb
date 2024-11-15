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
    prompt_2 = "Please make a note, today is November 15th, 2024, and I am just beginning my final project for Application Development."
    prompt_3 = "Please create a note, I have just been thinking about how sad the weather is, it reminds me of London where it is cold and it is gray and it is sad."

    openai_class = OpenaiService.new

    @result = openai_class.prompt_classify(message: prompt_1)
    render({:template => "main_templates/processing"})
  end
end
