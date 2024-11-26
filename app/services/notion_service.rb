# app/services/notion_service.rb

class NotionService
  attr_reader :action_log

  # Database IDs
  DATABASES = {
    notes: ENV.fetch("NOTES_DB_KEY"),
    tasks: ENV.fetch("TASKS_DB_KEY"),
    people: ENV.fetch("PEOPLE_DB_KEY"),
    classes: ENV.fetch("CLASSES_DB_KEY"),
    companies: ENV.fetch("COMPANIES_DB_KEY"),
    ingredients: ENV.fetch("INGREDIENTS_DB_KEY"),
    recipes: ENV.fetch("RECIPES_DB_KEY")
  }.freeze

  # Schema Definitions
  SCHEMA = {
    notes: {
      title: { name: 'Meeting', type: 'title' },
      date: { name: 'Date', type: 'date' },
      relations: {
        people: { name: 'People', type: 'relation', database: :people },
        companies: { name: 'Company', type: 'relation', database: :companies },
        classes: { name: 'Class', type: 'relation', database: :classes }
      }
    },
    tasks: {
      title: { name: 'Name', type: 'title' },
      deadline: { name: 'Deadline', type: 'date' },
      action_date: { name: 'Action Date', type: 'date' },
      status: { name: 'Status', type: 'status' },
      relations: {
        people: { name: 'People', type: 'relation', database: :people },
        companies: { name: 'Company', type: 'relation', database: :companies },
        classes: { name: 'Class', type: 'relation', database: :classes }
      }
    },
    ingredients: {
      title: { name: 'Ingredient', type: 'title' },
      amount_needed: { name: 'Amount Needed', type: 'number' },
      relations: {
        company: { name: 'Company', type: 'relation', database: :companies }
      }
    },
    recipes: {
      title: { name: 'Name', type: 'title' },
      planned: { name: 'Planned', type: 'checkbox' },
      relations: {
        company: { name: 'Company', type: 'relation', database: :companies }
      }
    },
    recommendations: {
      title: { name: 'Name', type: 'title'},
      #status: { name: 'Status', type: 'status' },
      relations: {
        people: {name: 'Recommender', type: 'relation', database: :people}
      }
    },
    ideas: {
      title: {name: 'Name', type: 'title' }
    },
    people: {
      title: { name: 'Name', type: 'title' }
    },
    classes: {
      title: { name: 'Course Title', type: 'title' }
    },
    companies: {
      title: { name: 'Name', type: 'title' }
    }
  }.freeze

  # Base URL for Notion pages
  NOTION_BASE_URL = ENV.fetch("NOTION_BASE_URL", "https://www.notion.so/")

  def initialize
    @client = Notion::Client.new
    @action_log = []
  end

  # Method to construct Notion page URL
  def construct_notion_url(page_id)
    # Remove dashes from page_id
    formatted_id = page_id.gsub(/-/, '')
    "#{NOTION_BASE_URL}#{formatted_id}"
  end

  def get_page_title(page_id)
    Rails.logger.debug "Retrieving title for Page ID: #{page_id}"
  
    begin
      # Fetch page details
      page = @client.page(page_id: page_id)
  
      # Retrieve the title property based on your schema
      title_property_name = SCHEMA[:notes][:title][:name] # Adjust this based on the database type
      title_property = page.dig("properties", title_property_name, "title")
  
      # Extract the plain text from the title array
      if title_property.is_a?(Array) && title_property.any?
        title_property.map { |text_block| text_block["plain_text"] }.join(" ")
      else
        "Untitled Page"
      end
    rescue Notion::Api::Errors::NotionError => e
      Rails.logger.error "Error retrieving title for Page ID #{page_id}: #{e.message}"
      "Error fetching title"
    end
  end

  def find_page_by_title(database_key, title)
    Rails.logger.debug "Finding page in database_key: #{database_key}, title: #{title}"
    database_id = DATABASES[database_key]
    unless database_id
      Rails.logger.error "Database ID for #{database_key} not found."
      return nil
    end
  
    title_property = SCHEMA[database_key][:title][:name]
    filter = {
      property: title_property,
      title: {
        equals: title
      }
    }
  
    response = @client.database_query(
      database_id: database_id,
      filter: filter
    )
  
    if response && response['results'] && !response['results'].empty?
      page = response['results'].first
      return page
    else
      Rails.logger.warn "No page found for title '#{title}' in database '#{database_key}'."
      return nil
    end
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error querying database #{database_key}: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    return nil
  end

  # General Method to Retrieve a Property Value from a Page
  def get_property_value(page:, property_name:)
    property = page['properties'][property_name] rescue nil
    return nil unless property

    case property['type']
    when 'number'
      return property['number']
    when 'checkbox'
      return property['checkbox']
    when 'title'
      return property['title'].map { |t| t['plain_text'] }.join
    else
      nil
    end
  end

  # General method to update page properties
  def update_page_properties(page_id, properties)
    @client.update_page(
      page_id: page_id,
      properties: properties
    )
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error updating page #{page_id}: #{e.message}"
  end

  # Method to construct property value based on type
  def construct_property_value(type, value)
    case type
    when 'title'
      { 'title' => [{ 'text' => { 'content' => value } }] }
    when 'number'
      { 'number' => value }
    when 'checkbox'
      { 'checkbox' => value }
    when 'date'
      { 'date' => { 'start' => value } }
    when 'relation'
      { 'relation' => value.map { |id| { 'id' => id } } }
    when 'status'
      { 'status' => { 'name' => value } }
    else
      {}
    end
  end

  # Method to find or create an entity with direct and indirect matching
  def find_or_create_entity(name:, relation_field:)
    db_key = relation_field.to_sym
    page = find_page_by_title(db_key, name)
  
    if page
      return [page['id'], 'direct']
    else
      titles = get_all_titles_from_database(db_key)
      best_match = find_best_match(search_term: name, options: titles)
  
      if best_match && best_match != "No match"
        matched_page = find_page_by_title(db_key, best_match)
        return [matched_page['id'], 'indirect'] if matched_page
      end
  
      new_page = create_entity(db_key, name)
      return [new_page['id'], 'created']
    end
  end

  def add_relations_to_page(page_id:, relations_hash:, item_type:)
    properties = {}
  
    # Pluralize the item_type to match SCHEMA keys
    plural_item_type = item_type.pluralize.to_sym
  
    relations_hash.each do |relation_field, page_ids|
      # Fetch the correct property name from the SCHEMA using plural_item_type
      property_schema = SCHEMA[plural_item_type]&.dig(:relations, relation_field)
  
      if property_schema && property_schema[:name]
        property_name = property_schema[:name]
        properties[property_name] = {
          'relation' => page_ids.map { |id| { 'id' => id } }
        }
      else
        @action_log << "Relation field '#{relation_field}' not found in SCHEMA for item type '#{plural_item_type}'."
        Rails.logger.error "Relation field '#{relation_field}' not found in SCHEMA for item type '#{plural_item_type}'."
      end
    end
  
    # Proceed only if there are valid properties to update
    if properties.any?
      @client.update_page(
        page_id: page_id,
        properties: properties
      )
      @action_log << "Added relations to page ID '#{page_id}'."
    else
      @action_log << "No valid relations to add for page ID '#{page_id}'."
    end
  
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Failed to add relations: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    raise
  end

  # Helper method to get all titles from a database
  def get_all_titles_from_database(database_key)
    database_id = DATABASES[database_key]
    title_property = SCHEMA[database_key][:title][:name]

    titles = []
    start_cursor = nil
    loop do
      params = { database_id: database_id, page_size: 100 }
      params[:start_cursor] = start_cursor if start_cursor

      response = @client.database_query(**params)
      response['results'].each do |page|
        title = get_property_value(page: page, property_name: title_property)
        titles << title if title
      end
      start_cursor = response['next_cursor']
      break unless start_cursor
    end

    titles
  end

  # Helper method to find the best match using OpenAI
  def find_best_match(search_term:, options:)
    openai_service = OpenaiService.new
    openai_service.find_best_match(search_term: search_term, options: options)
  end

  # Helper method to create a new entity
  def create_entity(database_key, name)
    title_property = SCHEMA[database_key][:title]
    properties = {
      title_property[:name] => construct_property_value(title_property[:type], name)
    }

    response = @client.create_page(
      parent: { database_id: DATABASES[database_key] },
      properties: properties
    )

    @action_log << "Created new #{database_key.to_s.capitalize} '#{name}'."
    response
  end

  # Method to add a note
  def add_note(title:, body:, date:, relations: {})
    db_id = DATABASES[:notes]
    properties = {
      SCHEMA[:notes][:title][:name] => {
        'title' => [
          {
            'text' => {
              'content' => title
            }
          }
        ]
      },
      SCHEMA[:notes][:date][:name] => {
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
                'content' => body
              }
            }
          ]
        }
      }
    ]

    response = @client.create_page(
      parent: { database_id: db_id },
      properties: properties,
      children: children
    )

    page_id = response['id']
    page_url = construct_notion_url(page_id)
    page_title = get_page_title(page_id)

    @action_log << { message: "Created Note: '#{page_title}'", url: page_url }
    response
  end

  # Method to add a task
  def add_task(task_name:, deadline:, action_date:, relations: {})
    db_id = DATABASES[:tasks]
    properties = {
      SCHEMA[:tasks][:title][:name] => {
        'title' => [
          {
            'text' => {
              'content' => task_name
            }
          }
        ]
      },
      SCHEMA[:tasks][:deadline][:name] => {
        'date' => {
          'start' => deadline
        }
      },
      SCHEMA[:tasks][:action_date][:name] => {
        'date' => {
          'start' => action_date
        }
      },
      SCHEMA[:tasks][:status][:name] => {
        'status' => {
          'name' => 'Next'
        }
      }
    }

    response = @client.create_page(
      parent: { database_id: db_id },
      properties: properties
    )

    page_id = response['id']
    page_url = construct_notion_url(page_id)
    page_title = get_page_title(page_id)

    @action_log << { message: "Created Task: '#{page_title}'", url: page_url }
    response
  end

  # Method to add a task
  def add_recommendation(name:, type:, relations: {})
    db_id = DATABASES[:tasks]
    properties = {
      SCHEMA[:recommendations][:title][:name] => {
        'title' => [
          {
            'text' => {
              'content' => name
            }
          }
        ]
      }
    }

    response = @client.create_page(
      parent: { database_id: db_id },
      properties: properties
    )

    page_id = response['id']
    page_url = construct_notion_url(page_id)
    page_title = get_page_title(page_id)

    @action_log << { message: "Created Recommendation: '#{page_title}'", url: page_url }
    response
  end

  # Method to update multiple ingredients
  def update_ingredients(ingredients)
    ingredients.each do |ingredient|
      name = ingredient['name']
      quantity_to_add = ingredient['quantity'].to_i

      page_id, match_type = find_or_create_entity(name: name, relation_field: :ingredients)

      if page_id
        current_amount = get_property_value(page: page_id, property_name: 'Amount Needed') || 0
        new_amount = current_amount + quantity_to_add

        properties = {
          'Amount Needed' => construct_property_value('number', new_amount)
        }

        update_page_properties(page_id, properties)
        ingredient['page_id'] = page_id
        ingredient['match_type'] = match_type
        page_url = construct_notion_url(page_id)
        page_title = get_page_title(page_id)

        @action_log << { message: "Updated Ingredient: '#{page_title}' to Quantity: #{new_amount}", url: page_url }
      else
        @action_log << { message: "Failed to process Ingredient: '#{name}'", url: nil }
      end
    end
  end

  # Method to update multiple recipes
  def update_recipes(recipes)
    recipes.each do |recipe|
      page_id, match_type = find_or_create_entity(name: recipe, relation_field: :recipes)

      if page_id
        properties = {
          'Planned' => construct_property_value('checkbox', true)
        }

        update_page_properties(page_id, properties)
        page_url = construct_notion_url(page_id)
        page_title = get_page_title(page_id)

        @action_log << { message: "Marked Recipe as Planned: '#{page_title}'", url: page_url }
      else
        @action_log << { message: "Failed to process Recipe: '#{recipe}'", url: nil }
      end
    end
  end

  def construct_notion_url(page_id)
    formatted_id = page_id.gsub(/-/, '')
    "#{NOTION_BASE_URL}#{formatted_id}"
  end

  def log_action_with_title(page_id, relations)
    title = get_page_title(page_id)
    page_link = "[#{title}](https://www.notion.so/#{page_id})"
  
    relations_descriptions = relations.map do |relation_field, related_page_ids|
      related_titles = related_page_ids.map { |id| get_page_title(id) }
      "#{relation_field.capitalize}: #{related_titles.join(', ')}"
    end.join("; ")
  
    "Page created: #{page_link} with relations: #{relations_descriptions}."
  end
end
