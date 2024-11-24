# app/services/notion_service.rb

class NotionService

  NOTES_DB_ID = ENV.fetch("NOTES_DB_KEY")
  TASKS_DB_ID = ENV.fetch("TASKS_DB_KEY")
  PEOPLE_DB_ID = ENV.fetch("PEOPLE_DB_KEY")
  CLASSES_DB_ID = ENV.fetch("CLASSES_DB_KEY")
  COMPANIES_DB_ID = ENV.fetch("COMPANIES_DB_KEY")
  INGREDIENTS_DB_ID = ENV.fetch("INGREDIENTS_DB_KEY")
  RECIPES_DB_ID = ENV.fetch("RECIPES_DB_KEY")

  # For Notes
  NOTES_TITLE_PROPERTY = 'Meeting'
  NOTES_RELATIONS = {
    'People' => 'People',
    'Company' => 'Company',
    'Course' => 'Course'
  }

  # For Tasks
  TASKS_TITLE_PROPERTY = 'Name'
  TASKS_RELATIONS = {
    'People' => 'People',
    'Organization' => 'Organization'
  }

  attr_reader :action_log

  def initialize
    @client = Notion::Client.new
  end

  # Function 1 - Search Notion Database by Page Title
  def search_page_by_title(database_id:, page_title:, title_property: 'Name')
    filter = {
      property: title_property,
      title: {
        equals: page_title
      }
    }

    response = @client.database_query(
      database_id: database_id,
      filter: filter
    )

    if response && response['results'] && !response['results'].empty?
      page = response['results'].first
      page_id = page['id']
      return page_id
    else
      return nil
    end
  end

  # Function 2 - Search Notion Database for Indirect Matches with OpenAI
  def search_page_by_indirect_match(database_id:, search_term:, title_property: 'Name')
    pages = []
    start_cursor = nil
    loop do
      response = @client.database_query(database_id: database_id, start_cursor: start_cursor)
      pages += response['results']
      start_cursor = response['next_cursor']
      break unless start_cursor
    end

    page_titles = pages.map do |page|
      {
        id: page['id'],
        title: extract_title_from_page(page: page, title_property: title_property)
      }
    end

    openai_service = OpenaiService.new
    best_match = openai_service.find_best_match(search_term: search_term, options: page_titles.map { |p| p[:title] })

    if best_match
      matched_page = page_titles.find { |p| p[:title] == best_match }
      return matched_page
    else
      return nil
    end
  end

  # Function to find or create an entity and return its page ID
  def find_or_create_entity(name:, type:)
    case type
    when 'person'
      db_id = PEOPLE_DB_ID
      title_property = 'Name'
    when 'class'
      db_id = CLASSES_DB_ID
      title_property = 'Name'
    when 'company'
      db_id = COMPANIES_DB_ID
      title_property = 'Name'
    else
      return nil
    end

    # Try direct match
    page_id = search_page_by_title(database_id: db_id, page_title: name, title_property: title_property)

    if page_id.nil?
      # Try indirect match
      matched_page = search_page_by_indirect_match(database_id: db_id, search_term: name, title_property: title_property)
      if matched_page
        page_id = matched_page[:id]
      else
        # Create new page
        page = create_entity_page(database_id: db_id, name: name, title_property: title_property)
        page_id = page['id']
        @action_log << "Created new page '#{name}' in #{type.capitalize} database."
      end
    end

    return page_id
  end

  def create_entity_page(database_id:, name:, title_property:)
    properties = {
      title_property => {
        'title' => [
          {
            'text' => {
              'content' => name
            }
          }
        ]
      }
    }

    page = @client.create_page(
      parent: { database_id: database_id },
      properties: properties
    )

    return page
  end

  # Function 3 - Add Relation (Handles multiple relations independently)
  def add_relations_to_page(page_id:, relations_hash:, relation_fields:)
    relations_hash.each do |relation_field, page_ids|
      next unless relation_field

      properties = {
        relation_field => {
          'relation' => page_ids.map { |id| { 'id' => id } }
        }
      }

      @client.update_page(
        page_id: page_id,
        properties: properties
      )

      @action_log << "Added relation '#{relation_field}' to page ID '#{page_id}'."
    end
  end

  def add_note(title:, body:, formatted_date:)
    properties = {
      NOTES_TITLE_PROPERTY => {
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

    response = @client.create_page(
      parent: { database_id: NOTES_DB_ID },
      properties: properties,
      children: children
    )

    @action_log << "Created new Note '#{title}' with body: '#{body}'."

    return response
  end

  def add_task(task_name:, due_date:, action_date:)
    properties = {
      TASKS_TITLE_PROPERTY => {
        'title' => [
          {
            'text' => {
              'content' => task_name
            }
          }
        ]
      },
      'Deadline' => {
        'date' => {
          'start' => due_date
        }
      },
      'Action Date' => {
        'date' => {
          'start' => action_date
        }
      },
      'Status' => {
        'status' => {
          'name' => 'Next'
        }
      }
    }

    response = @client.create_page(
      parent: { database_id: TASKS_DB_ID },
      properties: properties
    )

    @action_log << "Created new Task '#{task_name}' with deadline '#{due_date}' and action date '#{action_date}'."

    return response
  end

  # Helper method to extract the title from a page
  def extract_title_from_page(page:, title_property: 'Name')
    title_data = page['properties'][title_property]['title']
    title_text = title_data.map { |t| t['plain_text'] }.join
    return title_text
  end
end
