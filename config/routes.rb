# config / routes.rb

Rails.application.routes.draw do

  # This is a blank app! Pick your first screen, build out the RCAV, and go from there. E.g.:

  # get "/your_first_screen" => "pages#first"
  
  get("/", {:controller => "main", :action => "main"})

  get("/processing", {:controller => "main", :action => "processing"})

  post("/submit", {:controller => "main", :action => "submit"})
end
