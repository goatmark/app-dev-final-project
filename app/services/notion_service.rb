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

  # New constant mapping database keys to their title property names
  TITLE_PROPERTIES = {
    notes: 'Meeting',
    tasks: 'Name',
    people: 'Name',
    classes: 'Course Title',
    companies: 'Name',
    ingredients: 'Ingredient',
    recipes: 'Name',
    recommendations: 'Name',
    ideas: 'Name'
  }.freeze

  # Base URL for Notion pages
  NOTION_BASE_URL = ENV.fetch("NOTION_BASE_URL", "https://www.notion.so/")

  def initialize
    @client = Notion::Client.new
    @action_log = []
  end

  # General method to create a page with a payload
  def create_page(payload)
    response = @client.create_page(payload)
    page_id = response['id']
    page_url = construct_notion_url(page_id)
    page_title = get_page_title(page_id)

    @action_log << { message: "Created page: '#{page_title}'", id: page_id, title: page_title, url: page_url }
    response
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error creating page: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    nil
  end

  # General method to update a page with properties
  def update_page(page_id, properties:)
    @client.update_page(page_id: page_id, properties: properties)
    @action_log << { message: "Updated page properties for page ID '#{page_id}'" }
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Error updating page #{page_id}: #{e.message}"
    Rails.logger.error "Notion API Error when updating page_id #{page_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  # Helper method to construct properties
  def construct_properties(properties_hash)
    properties = {}
    properties_hash.each do |name, info|
      type = info[:type]
      value = info[:value]
      properties.merge!(construct_property(name, type, value))
    end
    properties
  end

  # Method to construct individual property
  def construct_property(name, type, value)
    case type
    when 'title'
      { name => { 'title' => [{ 'text' => { 'content' => value } }] } }
    when 'number'
      { name => { 'number' => value } }
    when 'checkbox'
      { name => { 'checkbox' => value } }
    when 'date'
      { name => { 'date' => { 'start' => value } } }
    when 'relation'
      { name => { 'relation' => value.map { |id| { 'id' => id } } } }
    when 'status'
      { name => { 'status' => { 'name' => value } } }
    else
      {}
    end
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

  # Helper to construct Notion page URL
  def construct_notion_url(page_id)
    formatted_id = page_id.gsub(/-/, '')
    "#{NOTION_BASE_URL}#{formatted_id}"
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

  # Modified method to include indirect matching and control over page creation
  def find_or_create_entity(name:, database_key:, allow_creation: true)
    Rails.logger.debug "find_or_create_entity() method"
    Rails.logger.debug "Name: #{name}"
    Rails.logger.debug "DB Key: #{database_key}"
    page = find_page_by_title(database_key, name)
    if page
      Rails.logger.debug "Page: #{page['id']}"
      Rails.logger.debug "Page #{page['id']} was a direct match!"
      return [page['id'], 'direct']
    else
      Rails.logger.debug "No page found for title '#{name}' in database '#{database_key}'."
      titles = get_all_titles_from_database(database_key)

      # Try indirect match with RegEx
      best_match = indirect_match_with_regex(search_term: name, options: titles)
      if best_match
        matched_page = find_page_by_title(database_key, best_match)
        return [matched_page['id'], 'indirect'] if matched_page
      end

      # If high confidence match not found, try with OpenAI (if allowed)
      if allow_creation
        best_match = find_best_match(search_term: name, options: titles)
        if best_match && best_match != "No match"
          matched_page = find_page_by_title(database_key, best_match)
          return [matched_page['id'], 'openai'] if matched_page
        end

        # If still no match, create a new page
        title_property_name = TITLE_PROPERTIES[database_key] || 'Name'
        properties = construct_property(title_property_name, 'title', name)
        payload = {
          parent: { database_id: DATABASES[database_key] },
          properties: properties
        }
        response = create_page(payload)
        [response['id'], 'created']
      else
        # Do not create new page, return nil
        Rails.logger.warn "No match found and allow_creation is false. Skipping creation."
        return [nil, 'no_match']
      end
    end
  end

  # Helper method for indirect matching using RegEx
  def indirect_match_with_regex(search_term:, options:)
    search_terms = search_term.downcase.split(/\s+/)
    best_match = nil
    highest_score = 0
    options.each do |option|
      option_terms = option.downcase.split(/\s+/)
      common_terms = search_terms & option_terms
      score = common_terms.size
      if score > highest_score
        highest_score = score
        best_match = option
      end
    end
    return best_match if highest_score > 0
    nil
  end

  # Helper method to find the best match using OpenAI
  def find_best_match(search_term:, options:)
    openai_service = OpenaiService.new
    openai_service.find_best_match(search_term: search_term, options: options)
  end

  # General method to find a page by title
  def find_page_by_title(database_key, title)
    Rails.logger.debug "Find Page by Title Method"

    database_id = DATABASES[database_key]
    title_property_name = TITLE_PROPERTIES[database_key] || 'Name' # Use the correct title property
    Rails.logger.debug "Title Property Name: #{title_property_name}"
    filter = {
      property: title_property_name,
      title: { equals: title }
    }
    Rails.logger.debug "Filter: #{filter}"
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

  # Helper method to get all titles from a database
  def get_all_titles_from_database(database_key)
    database_id = DATABASES[database_key]
    title_property_name = TITLE_PROPERTIES[database_key] || 'Name' # Use the correct title property

    titles = []
    start_cursor = nil
    loop do
      params = { database_id: database_id, page_size: 100 }
      params[:start_cursor] = start_cursor if start_cursor

      response = @client.database_query(**params)
      response['results'].each do |page|
        title = get_property_value(page: page, property_name: title_property_name)
        titles << title if title
      end
      start_cursor = response['next_cursor']
      break unless start_cursor
    end

    titles
  end

  # General method to update items (e.g., ingredients, recipes)
  def update_items(database_key, items, update_values = {}, allow_creation: true)
    items.each do |item|
      name = item['name']

      page_id, match_type = find_or_create_entity(name: name, database_key: database_key, allow_creation: allow_creation)

      if page_id
        page = @client.page(page_id: page_id)
        Rails.logger.debug "Fetched page for item: #{name}"
        input_values = update_values.call(page, item)
        Rails.logger.debug "Received input_values from update_values lambda: #{input_values}"

        properties = construct_properties(input_values)

        update_page(page_id, properties: properties)

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
