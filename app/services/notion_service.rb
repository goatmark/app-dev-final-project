# app/services/notion_service.rb

class NotionService
  attr_reader :action_log

  # Database IDs
  NOTES_DB_ID = ENV.fetch("NOTES_DB_KEY")
  TASKS_DB_ID = ENV.fetch("TASKS_DB_KEY")
  PEOPLE_DB_ID = ENV.fetch("PEOPLE_DB_KEY")
  CLASSES_DB_ID = ENV.fetch("CLASSES_DB_KEY")
  COMPANIES_DB_ID = ENV.fetch("COMPANIES_DB_KEY")
  INGREDIENTS_DB_ID = ENV.fetch("INGREDIENTS_DB_KEY")
  RECIPES_DB_ID = ENV.fetch("RECIPES_DB_KEY")

  # For Notes
  NOTES_TITLE_PROPERTY = 'Name'
  NOTES_RELATIONS = {
    'People' => PEOPLE_DB_ID,
    'Company' => COMPANIES_DB_ID,
    'Course' => CLASSES_DB_ID
  }

  # For Tasks
  TASKS_TITLE_PROPERTY = 'Name'
  TASKS_RELATIONS = {
    'People' => PEOPLE_DB_ID,
    'Organization' => COMPANIES_DB_ID,
    'Course' => CLASSES_DB_ID
  }

  def initialize
    @client = Notion::Client.new
    @action_log = []
  end

  def add_note(title:, body:, date:)
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
          'start' => date
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

    @action_log << "Created new Note '#{title}'."

    return response
  end

  def add_task(name:, deadline:, action_date:)
    properties = {
      TASKS_TITLE_PROPERTY => {
        'title' => [
          {
            'text' => {
              'content' => name
            }
          }
        ]
      },
      'Deadline' => {
        'date' => {
          'start' => deadline
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

    @action_log << "Created new Task '#{name}'."

    return response
  end

  def add_relations_to_page(page_id:, relations_hash:)
    properties = {}

    relations_hash.each do |relation_field, page_ids|
      properties[relation_field] = {
        'relation' => page_ids.map { |id| { 'id' => id } }
      }
    end

    @client.update_page(
      page_id: page_id,
      properties: properties
    )

    @action_log << "Added relations to page ID '#{page_id}'."
  end

  def find_or_create_entity(name:, relation_field:)
    db_id = NOTES_RELATIONS[relation_field] || TASKS_RELATIONS[relation_field]
    return nil, nil unless db_id

    # Set the correct title property for each database
    title_property = 'Name' # Adjust if your databases use a different title property

    type = get_entity_type_for_relation_field(relation_field)

    # Clean the search term
    openai_service = OpenaiService.new
    cleaned_name = openai_service.clean_search_term(name)

    # Try direct match with cleaned name
    page_id = search_page_by_title(database_id: db_id, page_title: cleaned_name, title_property: title_property)

    if page_id
      match_type = 'direct'
      @action_log << "Directly matched '#{cleaned_name}' to existing #{type} page."
    else
      # Get all titles from the database
      titles = get_all_titles_from_database(database_id: db_id, title_property: title_property)

      # Try indirect match using OpenAI with cleaned name
      best_match = openai_service.find_best_match(search_term: cleaned_name, options: titles)

      if best_match
        # Find the page ID of the best match
        matched_page_id = search_page_by_title(database_id: db_id, page_title: best_match.strip, title_property: title_property)
        if matched_page_id
          page_id = matched_page_id
          match_type = 'indirect'
          @action_log << "Indirectly matched '#{cleaned_name}' to '#{best_match}' in #{type.capitalize} database."
        else
          match_type = 'no_match'
          @action_log << "No matching page found for '#{cleaned_name}' in #{type.capitalize} database."
        end
      else
        match_type = 'no_match'
        @action_log << "No matching page found for '#{cleaned_name}' in #{type.capitalize} database."
      end
    end

    return page_id, match_type
  end

  def search_page_by_title(database_id:, page_title:, title_property:)
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

  def get_all_titles_from_database(database_id:, title_property:)
    pages = []
    start_cursor = nil
    loop do
      response = @client.database_query(database_id: database_id, start_cursor: start_cursor, page_size: 100)
      pages += response['results']
      start_cursor = response['next_cursor']
      break unless start_cursor
    end

    titles = pages.map do |page|
      extract_title_from_page(page: page, title_property: title_property)
    end

    return titles.compact.uniq
  end

  def extract_title_from_page(page:, title_property:)
    title_data = page['properties'][title_property]['title']
    return nil unless title_data
    title_text = title_data.map { |t| t['plain_text'] }.join
    return title_text.strip
  end

  def get_entity_type_for_relation_field(relation_field)
    case relation_field
    when 'People'
      'person'
    when 'Company', 'Organization'
      'company'
    when 'Course'
      'class'
    else
      nil
    end
  end
end
