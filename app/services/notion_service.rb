# app/services/notion_service.rb

class NotionService
  def initialize
    @client = Notion::Client.new
  end

  def add_note(body, formatted_date)
    db = ENV.fetch("NOTES_DB_KEY")
    properties = {
      'Meeting': {
        'title': [
          {
            'text': {
              'content': body 
            }
          }
        ]
      },
      'Date': {
        'date': {
          'start': formatted_date
        }
      }
    }
    @client.create_page(
      parent: { database_id: ENV.fetch("NOTES_DB_KEY")},
      properties: properties    
    )

  end

  def add_task()
    db = ENV.fetch("TASKS_DB_KEY")
  end
end
