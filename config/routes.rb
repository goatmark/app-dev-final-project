# config/routes.rb

Rails.application.routes.draw do
  root 'main#main'
  post '/submit', to: 'main#submit'
  post '/upload_audio', to: 'main#upload_audio'
  get '/processing', to: 'main#processing'
  post '/confirm', to: 'main#confirm'
end
