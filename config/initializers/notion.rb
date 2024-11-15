# config / intializers / notion.rb
Notion.configure do |config|
  config.token = ENV.fetch("NOTION_KEY") { raise "Notion key not set in environment variables" }
end
