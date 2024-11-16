# app/services/notion_service.rb

class NotionService
  def initialize
    @client = Notion::Client.new
  end

  def add_note(title, body, formatted_date)
    db_id = ENV.fetch("NOTES_DB_KEY")
    properties = {
      'Meeting' => {
        'title' => [
          {
            'text' => {
              'content' => title
            }
          }
        ]
      },
      'Date' => {
        'date' => {
          'start' => formatted_date
        }
      }
    }

    # Define the content of the page as children blocks
    children = [
      {
        object: 'block',
        type: 'paragraph',
        paragraph: {
          rich_text: [
            {
              type: 'text',
              text: {
                content: body
              }
            }
          ]
        }
      }
    ]

    @client.create_page(
      parent: { database_id: db_id },
      properties: properties,
      children: children
    )

  end

  def add_task()
    db = ENV.fetch("TASKS_DB_KEY")
  end
end