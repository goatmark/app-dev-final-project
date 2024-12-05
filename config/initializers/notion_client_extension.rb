# config/initializers/notion_client_extension.rb

require Rails.root.join('app/services/notion_client_extension.rb')

Notion::Client.include(NotionClientExtension)
