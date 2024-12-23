# app/services/notion_service.rb

class NotionService
  attr_reader :action_log, :client

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
    ideas: ENV.fetch("IDEAS_DB_KEY"),
    wordle_games: ENV.fetch("WORDLE_GAMES_DB_KEY"),
    restaurants: ENV.fetch("RESTAURANTS_DB_KEY")
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
    ideas: 'Name',
    wordle_games: "#",
    restaurants: 'Name'
  }.freeze

  # Base URL for Notion pages
  NOTION_BASE_URL = "https://www.notion.so/"

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
    @client.block_append_children(block_id: page_id, children: children)
    @action_log << "Appended children to page ID '#{page_id}'."
  rescue Notion::Api::Errors::NotionError => e
    @action_log << "Failed to append children: #{e.message}"
    Rails.logger.error "Notion API Error: #{e.message}"
    raise
  end

  # Helper method to get the full content of a page
  def get_page_content(page_id)
    Rails.logger.debug "Fetching content for page ID: #{page_id}"
    blocks = []
    cursor = nil
    loop do
      begin
        response = @client.blocks_children_list(
          block_id: page_id,
          start_cursor: cursor,
          page_size: 100
        )
        Rails.logger.debug "Fetched #{response['results'].size} blocks."
        blocks += response['results']
        cursor = response['next_cursor']
        Rails.logger.debug "Next cursor: #{cursor}"
        break unless cursor
      rescue => e
        Rails.logger.error "Error fetching blocks for page ID #{page_id}: #{e.message}"
        raise e
      end
    end

    # Extract text from blocks
    content = blocks.map do |block|
      extract_text_from_block(block)
    end.compact.join("\n\n")

    Rails.logger.debug "Extracted content length: #{content.length}"
    content
  end

  # New method to gather information related to a task
  def gather_task_related_information(related_entities)
    gathered_info = {}

    related_entities.each do |entity|
      name = entity['name']
      type = entity['type']
      database_key = type.pluralize.to_sym

      page = find_page_by_title(database_key, name)
      if page
        page_content = get_page_content(page['id'])
        gathered_info["#{type.capitalize} - #{name}"] = page_content
      else
        Rails.logger.warn "No page found for #{type}: #{name}"
        gathered_info["#{type.capitalize} - #{name}"] = "No information available."
      end
    end

    # Fetch related notes
    notes = fetch_related_notes(related_entities)
    gathered_info["Related Notes"] = notes.map { |note| "#{note[:title]}\n#{note[:content]}" }.join("\n\n")

    gathered_info
  end

  # Helper method to extract text from a block
  def extract_text_from_block(block)
    case block['type']
    when 'paragraph'
      text = block['paragraph']['text'].map { |t| t['plain_text'] }.join
      Rails.logger.debug "Extracted paragraph: #{text}"
      text
    when 'heading_1', 'heading_2', 'heading_3'
      text = block[block['type']]['text'].map { |t| t['plain_text'] }.join
      Rails.logger.debug "Extracted heading: #{text}"
      text
    when 'bulleted_list_item', 'numbered_list_item'
      text = "- " + block[block['type']]['text'].map { |t| t['plain_text'] }.join
      Rails.logger.debug "Extracted list item: #{text}"
      text
    when 'toggle'
      text = block['toggle']['text'].map { |t| t['plain_text'] }.join
      Rails.logger.debug "Extracted toggle: #{text}"
      text
    when 'quote'
      text = "> " + block['quote']['text'].map { |t| t['plain_text'] }.join
      Rails.logger.debug "Extracted quote: #{text}"
      text
    when 'code'
      text = "```\n" + block['code']['text'].map { |t| t['plain_text'] }.join + "\n```"
      Rails.logger.debug "Extracted code block."
      text
    else
      Rails.logger.debug "Skipped unsupported block type: #{block['type']}"
      nil
    end
  rescue => e
    Rails.logger.error "Error extracting text from block: #{e.message}"
    nil
  end

  # Helper method to fetch related notes
  def fetch_related_notes(related_entities)
    # Assuming there's a 'Notes' database and each note has relations to people, classes, or companies
    # Build a filter to find notes related to any of the entities
    relation_filters = related_entities.map do |entity|
      {
        "property": entity['type'].capitalize,
        "relation": {
          "contains": find_page_by_title(entity['type'].pluralize.to_sym, entity['name'])&.dig('id')
        }
      }
    end

    # Combine filters with OR
    filter = {
      "or": relation_filters
    }

    notes = []
    cursor = nil
    loop do
      response = @client.database_query(
        database_id: DATABASES[:notes],
        filter: filter,
        start_cursor: cursor,
        page_size: 100
      )
      response['results'].each do |page|
        title = get_property_value(page: page, property_name: 'Meeting') # Adjust based on your title property
        content = get_page_content(page['id'])
        notes << { title: title, content: content }
      end
      cursor = response['next_cursor']
      break unless cursor
    end

    notes
  end

  # New method to update the body of a task with the generated plan
  def update_task_body(task_page_id, plan)
    Rails.logger.debug "Updating task body for page ID: #{task_page_id}"

    properties = {
      'Body' => {
        'rich_text' => [
          {
            'type' => 'text',
            'text' => {
              'content' => plan
            }
          }
        ]
      }
    }

    response = update_page(task_page_id, properties: properties)

    if response
      Rails.logger.debug "Successfully updated task body for page ID #{task_page_id}."
      @action_log << { message: "Task body updated with the generated plan.", url: construct_notion_url(task_page_id) }
    else
      Rails.logger.error "Failed to update task body for page ID #{task_page_id}."
      @action_log << { message: "Failed to update task body.", url: construct_notion_url(task_page_id) }
    end
  rescue => e
    Rails.logger.error "Error updating task body: #{e.message}"
    @action_log << { message: "Error updating task body: #{e.message}", url: construct_notion_url(task_page_id) }
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
  def find_page_by_title(database_key, raw_title)
    Rails.logger.debug "Find Page by Title Method"
    database_id = DATABASES[database_key]
    title_property_name = TITLE_PROPERTIES[database_key] || 'Name'
  
    # 1) Try EXACT match on the raw title
    exact_match_page = query_for_exact_match(database_id, title_property_name, raw_title)
    return exact_match_page if exact_match_page
  
    # 2) Try EXACT match on singular / plural forms
    singular = raw_title.singularize
    plural   = raw_title.pluralize
  
    [singular, plural].uniq.each do |term|
      exact_match_page = query_for_exact_match(database_id, title_property_name, term)
      return exact_match_page if exact_match_page
    end
  
    # 3) If we still have nothing, we do partial match (contains:)
    partial_matches = query_for_partial_match(database_id, title_property_name, raw_title)
    return nil if partial_matches.empty?
  
    return partial_matches.first if partial_matches.size == 1
  
    # 4) If multiple partial matches, pick the best fuzzy match
    best_page = pick_best_fuzzy_match(partial_matches, raw_title, title_property_name)
    if best_page
      Rails.logger.debug "Resolved multiple partial matches; best fuzzy match = #{best_page['id']}"
      return best_page
    else
      Rails.logger.warn "Could not fuzzy-match any page for '#{raw_title}' among multiple partial results."
      return nil
    end
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
      Rails.logger.debug "Item: #{item['name']}"
      Rails.logger.debug "DB Key: #{database_key}"

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

private

############################################################
# Helpers
############################################################

# Use the Notion filter: title => { equals: <some_string> }
# Return the single page if exactly one match; otherwise nil.
def query_for_exact_match(database_id, property_name, title_string)
  filter = {
    property: property_name,
    title: { equals: title_string }
  }
  response = @client.database_query(database_id: database_id, filter: filter)
  results = response['results']

  if results.size == 1
    page = results.first
    Rails.logger.debug "Exact match found for '#{title_string}': page #{page['id']}"
    return page
  elsif results.size > 1
    # If multiple exact matches, pick whichever you want, or do fuzzy picking.
    # For simplicity, let's pick the first.
    Rails.logger.warn "Multiple exact matches found for '#{title_string}'; returning first."
    return results.first
  end

  nil
end

# Use the Notion filter: title => { contains: <some_string> }
# Return the array of matched pages (could be empty or multiple)
def query_for_partial_match(database_id, property_name, title_string)
  filter = {
    property: property_name,
    title: { contains: title_string }
  }
  response = @client.database_query(database_id: database_id, filter: filter)
  response['results'] || []
end

# Among multiple pages, find the best match to `search_term` via Levenshtein distance
def pick_best_fuzzy_match(pages, search_term, property_name)
  pages_with_distance = pages.map do |page|
    page_title = get_property_value(page: page, property_name: property_name)
    distance   = levenshtein_distance(page_title.downcase, search_term.downcase)
    { page: page, title: page_title, distance: distance }
  end

  # Sort by ascending distance (lower = closer match)
  sorted = pages_with_distance.sort_by { |obj| obj[:distance] }
  best   = sorted.first
  best[:page]  # Return the actual page object
end

# Plain Ruby Levenshtein distance — no gems required
def levenshtein_distance(str1, str2)
  m = str1.length
  n = str2.length
  d = Array.new(m+1) { Array.new(n+1) }

  (0..m).each { |i| d[i][0] = i }
  (0..n).each { |j| d[0][j] = j }

  (1..m).each do |i|
    (1..n).each do |j|
      cost = (str1[i-1] == str2[j-1]) ? 0 : 1
      d[i][j] = [
        d[i-1][j] + 1,      # deletion
        d[i][j-1] + 1,      # insertion
        d[i-1][j-1] + cost  # substitution
      ].min
    end
  end

  d[m][n]
end

def query_for_exact_match(database_id, property_name, title_string)
  filter = {
    property: property_name,
    title: { equals: title_string }
  }
  response = @client.database_query(database_id: database_id, filter: filter)
  results = response['results']

  if results.size == 1
    page = results.first
    Rails.logger.debug "Exact match found for '#{title_string}': page #{page['id']}"
    return page
  elsif results.size > 1
    Rails.logger.warn "Multiple exact matches found for '#{title_string}'; returning first."
    return results.first
  end

  nil
end

# Use the Notion filter: title => { contains: <some_string> }
# Return the array of matched pages (could be empty or multiple)
def query_for_partial_match(database_id, property_name, title_string)
  filter = {
    property: property_name,
    title: { contains: title_string }
  }
  response = @client.database_query(database_id: database_id, filter: filter)
  response['results'] || []
end
