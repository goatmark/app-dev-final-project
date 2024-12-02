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
    recipes: ENV.fetch("RECIPES_DB_KEY"),
    recommendations: ENV.fetch("RECOMMENDATIONS_DB_KEY"),
    ideas: ENV.fetch("IDEAS_DB_KEY")
  }.freeze

  # Schema Definitions
  SCHEMA = {
    notes: {
      properties: {
        title: { name: 'Meeting', type: 'title' },
        date: { name: 'Date', type: 'date' }
      },
      relations: {
        people: { name: 'People', type: 'relation', database: :people },
        companies: { name: 'Company', type: 'relation', database: :companies },
        classes: { name: 'Class', type: 'relation', database: :classes }
      }
    },
    tasks: {
      properties: {
        title: { name: 'Name', type: 'title' },
        deadline: { name: 'Deadline', type: 'date' },
        action_date: { name: 'Action Date', type: 'date' },
        status: { name: 'Status', type: 'status' }
      },
      relations: {
        people: { name: 'People', type: 'relation', database: :people },
        companies: { name: 'Company', type: 'relation', database: :companies },
        classes: { name: 'Class', type: 'relation', database: :classes }
      }
    },
    ingredients: {
      properties: {
        title: { name: 'Ingredient', type: 'title' },
        amount_needed: { name: 'Amount Needed', type: 'number' }
      },
      relations: {
        company: { name: 'Company', type: 'relation', database: :companies }
      }
    },
    recipes: {
      properties: {
        title: { name: 'Name', type: 'title' },
        planned: { name: 'Planned', type: 'checkbox' }
      },
      relations: {
        company: { name: 'Company', type: 'relation', database: :companies }
      }
    },
    recommendations: {
      properties: {
        title: { name: 'Name', type: 'title' }
        #status: { name: 'Status', type: 'status' } # Uncomment if needed
      },
      relations: {
        people: { name: 'People', type: 'relation', database: :people }
      }
    },
    ideas: {
      properties: {
        title: { name: 'Name', type: 'title' }
      }
    },
    people: {
      properties: {
        title: { name: 'Name', type: 'title' }
      }
    },
    classes: {
      properties: {
        title: { name: 'Course Title', type: 'title' }
      }
    },
    companies: {
      properties: {
        title: { name: 'Name', type: 'title' }
      }
    }
  }.freeze

  # Base URL for Notion pages
  NOTION_BASE_URL = ENV.fetch("NOTION_BASE_URL", "https://www.notion.so/")

  def initialize
    @client = Notion::Client.new
    @action_log = []
  end

  # General method to create a page
  def create_page(database_key:, input_values:, relations: {}, children: nil)
    database_id = DATABASES[database_key]
    properties = construct_properties(database_key: database_key, input_values: input_values, relations: relations)

    response = @client.create_page(
      parent: { database_id: database_id },
      properties: properties,
      children: children
    )

    page_id = response['id']
    page_url = construct_notion_url(page_id)
    page_title = get_page_title(page_id)

    @action_log << { message: "Created #{database_key.to_s.capitalize}: '#{page_title}'", id: page_id, title: page_title, url: page_url }
    return(page_id)
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error creating page in database #{database_key}: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    nil
  end

  # General method to update page properties
  def update_page(page_id:, input_values: {}, relations: {})
    Rails.logger.debug "Starting update_page for page_id: #{page_id}"

    page = @client.page(page_id: page_id)
    database_key = get_database_id_from_page_id(page_id)
    Rails.logger.debug "Identified database_key: #{database_key}"

    unless database_key
      Rails.logger.error "Could not identify database key for page_id: #{page_id}"
      return
    end
    Rails.logger.debug "Database key:: #{database_key}"
    Rails.logger.debug "Input Values: #{input_values}"
    Rails.logger.debug "Relations: #{relations}"
    properties = construct_properties(database_key: database_key, input_values: input_values, relations: relations)
    Rails.logger.debug "Constructed properties to update: #{properties}"

    @client.update_page(
      page_id: page_id,
      properties: properties
    )
    @action_log << { message: "Updated page properties for page ID '#{page_id}'" }
    Rails.logger.debug "Successfully updated page_id: #{page_id}"
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error updating page #{page_id}: #{e.message}"
    Rails.logger.error "Notion API Error when updating page_id #{page_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  # Helper method to construct properties based on the schema
  def construct_properties(database_key:, input_values:, relations: {})
    schema = SCHEMA[database_key]
    properties = {}

    Rails.logger.debug "Database Key: #{database_key}"
    Rails.logger.debug "Schema: #{schema}"
    # Construct properties
    schema[:properties]&.each do |key, prop_schema|
      Rails.logger.debug "Key: #{key}"
      Rails.logger.debug "Prop Schema: #{prop_schema}"
      Rails.logger.debug "Schema Properties: #{schema[:properties]}"
      value = input_values[key]
      Rails.logger.debug "Value: #{value}"
      properties[prop_schema[:name]] = construct_property_value(prop_schema[:type], value)
    end

    # Construct relations
    relations.each do |relation_key, related_page_ids|
      relation_schema = schema[:relations][relation_key]
      next unless relation_schema
      properties[relation_schema[:name]] = construct_property_value('relation', related_page_ids)
    end

    properties
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

  # General method to find or create an entity
  def find_or_create_entity(name:, database_key:)
    page = find_page_by_title(database_key, name)
    if page
      [page['id'], 'direct']
    else
      titles = get_all_titles_from_database(database_key)
      best_match = find_best_match(search_term: name, options: titles)
      if best_match && best_match != "No match"
        matched_page = find_page_by_title(database_key, best_match)
        return [matched_page['id'], 'indirect'] if matched_page
      end
      new_page = create_page(database_key: database_key, input_values: { title: name })
      [new_page['id'], 'created']
    end
  end

  # General method to find a page by title
  def find_page_by_title(database_key, title)
    database_id = DATABASES[database_key]
    title_property = SCHEMA[database_key][:properties][:title][:name]
    filter = {
      property: title_property,
      title: { equals: title }
    }

    response = @client.database_query(
      database_id: database_id,
      filter: filter
    )

    if response && response['results'] && !response['results'].empty?
      response['results'].first
    else
      Rails.logger.warn "No page found for title '#{title}' in database '#{database_key}'."
      nil
    end
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error querying database #{database_key}: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    nil
  end

  # General method to get property value from a page
  def get_property_value(page:, property_name:)
    property = page['properties'][property_name] rescue nil
    return nil unless property

    case property['type']
    when 'number'
      property['number']
    when 'checkbox'
      property['checkbox']
    when 'title'
      property['title'].map { |t| t['plain_text'] }.join
    when 'date'
      property['date']['start'] rescue nil
    when 'status'
      property['status']['name'] rescue nil
    when 'relation'
      property['relation'].map { |rel| rel['id'] }
    else
      nil
    end
  end

  # Method to append children to a page
  def append_children_to_page(page_id:, children:)
    @client.append_block_children(block_id: page_id, children: children)
    @action_log << "Appended children to page ID '#{page_id}'."
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Failed to append children: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    raise
  end

  # Helper method to get all titles from a database
  def get_all_titles_from_database(database_key)
    database_id = DATABASES[database_key]
    title_property = SCHEMA[database_key][:properties][:title][:name]

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

  # Method to get the page title
  def get_page_title(page_id)
    page = @client.page(page_id: page_id)
    title_property_name = page['properties'].find { |_, prop| prop['type'] == 'title' }&.first
    if title_property_name
      title = get_property_value(page: page, property_name: title_property_name)
      title || "Untitled Page"
    else
      "Untitled Page"
    end
  rescue Notion::Api::Errors::NotionError => e
    Rails.logger.error "Error retrieving title for Page ID #{page_id}: #{e.message}"
    "Error fetching title"
  end

  # Method to construct Notion page URL
  def construct_notion_url(page_id)
    formatted_id = page_id.gsub(/-/, '')
    "#{NOTION_BASE_URL}#{formatted_id}"
  end

  # OLD Helper method to identify database key from page
  def identify_database_key_from_page(page)
    parent = page.parent
    if parent.type == 'database_id'
      database_id = parent.database_id
      DATABASES.key(database_id)
    else
      nil
    end
  end

  # NEW Helper method to identify database key from page
  def get_database_id_from_page_id(page_id)
    client = Notion::Client.new
    page = client.page(page_id: page_id)
    parent = page.parent
  
    if parent.type == 'database_id'
      database_id = parent.database_id
      return database_id
    else
      # The page does not belong directly to a database
      return nil
    end
  rescue Notion::Api::Errors::NotionError => e
    puts "Error fetching page: #{e.message}"
    return nil
  end

  # General method to update items (e.g., ingredients, recipes)
  def update_items(database_key, items, update_values = {})
    items.each do |item|
      name = item['name']
      Rails.logger.debug "Processing item: #{name}"

      page_id, match_type = find_or_create_entity(name: name, database_key: database_key)
      Rails.logger.debug "Found or created page_id: #{page_id}, match_type: #{match_type}"

      if page_id
        page = @client.page(page_id: page_id)
        Rails.logger.debug "Fetched page for item: #{name}"

        # Call the update_values lambda and log the input and output
        Rails.logger.debug "Calling update_values lambda for item: #{item}"
        input_values = update_values.call(page, item)
        Rails.logger.debug "Received input_values from update_values lambda: #{input_values}"

        Rails.logger.debug "Updating page_id: #{page_id} with input_values: #{input_values}"

        update_page(page_id: page_id, input_values: input_values)

        item['page_id'] = page_id
        item['match_type'] = match_type
        page_url = construct_notion_url(page_id)
        page_title = get_page_title(page_id)

        @action_log << { message: "Updated #{database_key.to_s.capitalize} '#{page_title}'", url: page_url }
      else
        @action_log << { message: "Failed to process #{database_key.to_s.capitalize}: '#{name}'", url: nil }
        Rails.logger.error "Failed to find or create entity for name: #{name}"
      end
    end
  end
end
