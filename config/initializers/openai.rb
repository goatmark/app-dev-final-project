# config / intializers / openai.rb
OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_KEY") { raise "OpenAI key not set in environment variables" }
  config.log_errors = true
end
