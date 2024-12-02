# config/routes.rb

Rails.application.routes.draw do
  # Routes for the Activity resource:

  # CREATE
  post("/insert_activity", { :controller => "activities", :action => "create" })
          
  # READ
  get("/activities", { :controller => "activities", :action => "index" })
  
  get("/activities/:path_id", { :controller => "activities", :action => "show" })
  
  # UPDATE
  
  post("/modify_activity/:path_id", { :controller => "activities", :action => "update" })
  
  # DELETE
  get("/delete_activity/:path_id", { :controller => "activities", :action => "destroy" })

  #------------------------------

  # Routes for the Recording resource:

  # CREATE
  post("/insert_recording", { :controller => "recordings", :action => "create" })
          
  # READ
  get("/recordings", { :controller => "recordings", :action => "index" })
  
  get("/recordings/:path_id", { :controller => "recordings", :action => "show" })
  
  # UPDATE
  
  post("/modify_recording/:path_id", { :controller => "recordings", :action => "update" })
  
  # DELETE
  get("/delete_recording/:path_id", { :controller => "recordings", :action => "destroy" })

  #------------------------------

  root 'main#main'
  post '/submit', to: 'main#submit'
  post '/upload_audio', to: 'main#upload_audio'
  get '/processing', to: 'main#processing'
  post '/confirm', to: 'main#confirm'
  get '/fetch_events', to: 'main#fetch_events'
  get '/fetch_action_logs', to: 'main#fetch_action_logs'
end
