# app/services/openai_service.rb

require 'net/http/post/multipart' # Ensure this is at the top

class OpenaiService

  OPENAI_API_KEY = ENV.fetch("OPENAI_KEY")
  def initialize
    @client = OpenAI::Client.new
  end

  def transcribe_audio(audio_file_path:)
    uri = URI.parse("https://api.openai.com/v1/audio/transcriptions")
  
    # Create the multipart POST request
    File.open(audio_file_path) do |file|
      request = Net::HTTP::Post::Multipart.new uri.path,
        "file" => UploadIO.new(file, "audio/wav", File.basename(file)),
        "model" => "whisper-1",
        "language" => "en"
  
      # Set the Authorization header
      request["Authorization"] = "Bearer #{OPENAI_API_KEY}"
  
      # Execute the request
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
  
      # Handle the response
      if response.is_a?(Net::HTTPSuccess)
        result = JSON.parse(response.body)
        result["text"]
      else
        Rails.logger.error "OpenAI Transcription Error: #{response.body}"
        raise "Transcription failed with status #{response.code}"
      end
    end
  rescue => e
    Rails.logger.error "Exception in transcribe_audio: #{e.message}"
    raise e
  end

  def classify_message(message:)
    prompt = <<~PROMPT
      Classify the message as belonging to one of the following databases:
      - idea
      - ingredient
      - note
      - recipe
      - recommendation
      - task
      Each of these classifiers will lead to a set of appropriate events. Key examples:
      - Suggesting items should be added to the shopping list should update the 'ingredients' database such that 'Shopping List' field is true
      - Suggesting I intend to make something or cook something should be treated as a 'recipe' 
      - Suggesting something is a 'task' will proceed to extract its start date and deadline (where applicable)
      - Saying 'I should read more about nihilism' will create an entry on the 'recommendations' DB with "nihilism" as the title
      - Any ambiguity should default to 'note'
      Return only the classification with NO other text and without quotes.
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          {
            role: "system",
            content: prompt
          },
          { role: "user", content: message }
        ],
        temperature: 0
      }
    )
    classification = response.dig("choices", 0, "message", "content").strip.downcase
    return classification
  end

  def extract_task_summary(message:)
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "Extract only a summary of the task as if it were to be put on a To-Do list or Kanban board. Do not use any leading bullet/hyphen characters. If a deadline is specified, do not include it in the task summary; it will be extracted separately." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    task_summary = response.dig("choices", 0, "message", "content").strip
    return task_summary
  end

  def extract_recommendation_summary(message:)
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "Extract only the identified piece of media (book title, article title, etc). Only include the title. Do not include any other text. Do not include author name or any other information (unless the recommendation lacks a specific name or includes something like 'Books by David Wright' or 'Philosophy of Nietzsche' or 'Dr. Oz's Podcast' - in which case, returna helpful description that accurately captures the recommendation)." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    recommendation_summary = response.dig("choices", 0, "message", "content").strip
    return recommendation_summary
  end

  def extract_recommendation_type(message:)
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "Return only: 'Article', 'Book', 'Music', 'Podcast', or 'Topic / Person' without quotes based on what the piece of media identified in the message is most likely to belong to." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    recommendation_summary = response.dig("choices", 0, "message", "content").strip
    return recommendation_summary
  end

  def extract_deadline(message:)
    today = Date.today
    dow = today.strftime('%A')
    todays_date = today.strftime('%Y-%m-%d')
    tomorrow_date = (today + 1).strftime('%Y-%m-%d')
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "Return only the deadline knowing today is #{dow}, #{todays_date}. (e.g., if something says it's due Tuesday, assume it's due the first Tuesday after #{todays_date}). If no deadline specified, return #{tomorrow_date}. If something is to be done 'today', return #{todays_date}. If something is due 'next week', assume a 7-day deadline from today. If something is due 'next month', assume a deadline a full calendar month from today. Strictly always respond in 'YYYY-MM-DD' format without quotes. Assume something to be done 'end of the week' is due Friday." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    deadline = response.dig("choices", 0, "message", "content").strip
    return deadline
  end

  def extract_action_date(message:)
    today = Date.today
    todays_date = today.strftime('%Y-%m-%d')
    tomorrow_date = (today + 1).strftime('%Y-%m-%d')
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "Today's date is #{todays_date}. If the prompt contains information about a 'reminder', e.g., 'remind me in 2 days,' return only the corresponding date in 'YYYY-MM-DD' format. Do not confuse this with the deadline. If a prompt says 'Send out an email in 2 days,' you should return #{todays_date}. If a prompt says 'Remind me tomorrow to send an email in 2 days,' you should return only #{tomorrow_date}. If the prompt does not contain information about a reminder, return only #{todays_date}. Only ever return a date. Assume something to be done 'end of the week' is due Friday." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    action_date = response.dig("choices", 0, "message", "content").strip
    return action_date
  end

  def extract_note_title(message:)
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "The message contains the 'body' of a Note to be stored in a database. Return only a proposed 'title' for the note. Do not return anything other than a title without quotes. Keep it concise, salient, and descriptive, not poetic. Colons are strictly not allowed." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    title = response.dig("choices", 0, "message", "content").strip
    return title
  end

  def extract_note_body(message:)
    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "system", content: "Context: You are responsible for parsing elements of a dictation. Your job is to extract just the 'note' part of the message given to you, excluding any commands given to the dictation app. In other words, if receiving something that says 'Make a note that I need to...', return 'I need to...' onwards. Return the full note. Do NOT summarize, paraphrase, or copy edit. You may only make minor tweaks to address filler words (ums/likes), misspoken words, or fractured sentences. Do NOT summarize. Do NOT attempt to improve the quality of writing beyond specification." },
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    body = response.dig("choices", 0, "message", "content").strip
    return body
  end

  def extract_related_entities(message:)
    prompt = <<~PROMPT
      From the following message, extract all specific names of people, specific classes (courses offered at Booth), or companies mentioned that could be relations in a Notion database.
      Do not include generic terms or groups like "MBA students" or "students".
      For each entity, identify its type as one of: "person", "class", or "company".
      Return the results in JSON format as an array of objects with "name" and "type" keys.
      **Do not include any code block markers, triple backticks, or any additional text before or after the JSON.**
      Example:
      [
        {"name": "Mitch Matthews", "type": "person"},
        {"name": "Digital Marketing Lab", "type": "class"},
        {"name": "North Face", "type": "company"}
      ]
      Message: "#{message}"
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "user", content: prompt }
        ],
        temperature: 0.7
      }
    )

    # Log the API response for debugging
    @last_api_response = response.dig("choices", 0, "message", "content").strip

    # Remove any code block markers or extra whitespace
    json_str = @last_api_response.strip
    json_str = json_str.gsub(/```(?:json)?/, '').strip

    begin
      entities = JSON.parse(json_str)
      return entities
    rescue JSON::ParserError => e
      # Handle parsing errors
      puts "JSON Parsing Error: #{e.message}"
      puts "Response was: #{@last_api_response}"
      return []
    end
  end

  def find_best_match(search_term:, options:)
    options_list = options.join("\n")
    prompt = <<~PROMPT
      You are an assistant that helps match a given search term to the most relevant option from a list.

      Search Term: "#{search_term}"

      Options:
      #{options_list}

      Instructions:
      - Return only the exact text of the best matching option.
      - If the search term closely matches an option (even partially), return that option.
      - If no suitable match is found, return "No match".
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "user", content: prompt }
        ],
        temperature: 0.2
      }
    )

    result = response.dig("choices", 0, "message", "content").strip
    return nil if result.downcase.include?("no match")
    return result.strip
  end

  def clean_search_term(search_term)
    # Remove common titles/prefixes
    titles = ["Professor", "Dr.", "Dr", "Mr.", "Ms.", "Mrs."]
    regex = Regexp.union(titles.map { |t| /\b#{Regexp.escape(t)}\b/i })
    cleaned_term = search_term.gsub(regex, '').strip
    return cleaned_term
  end

  def extract_ingredients(message:)
    prompt = <<~PROMPT
      From the following message, extract all ingredients and their quantities to add to the shopping list.
      - Return the results in JSON format as an array of objects with "name" and "quantity" keys.
      - If no quantity is specified, default the quantity to 1.
      - Quantities should be integers.
      - Do not include any code block markers or additional text.

      Example:
      [
        {"name": "Onions", "quantity": 1},
        {"name": "Garlic Cloves", "quantity": 2},
        {"name": "Cinnamon", "quantity": 1},
        {"name": "Parsley", "quantity": 1}
      ]

      Message: "#{message}"
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "user", content: prompt }
        ],
        temperature: 0.7
      }
    )

    @last_api_response = response.dig("choices", 0, "message", "content").strip

    # Remove code block markers if present
    json_str = @last_api_response.gsub(/```(?:json)?/, '').strip

    begin
      ingredients = JSON.parse(json_str)
      return ingredients
    rescue JSON::ParserError => e
      puts "JSON Parsing Error: #{e.message}"
      puts "Response was: #{@last_api_response}"
      return []
    end
  end

  def extract_recipes(message:)
    prompt = <<~PROMPT
      From the following message, extract all recipe names that should be added to the plan.
      - Return the results in JSON format as an array of recipe names.
      - Do not include any code block markers or additional text.

      Example:
      [
        "Leek & Bacon Risotto",
        "Maroulosalata",
        "Mediterranean Tzatziki Breakfast Wrap"
      ]

      Message: "#{message}"
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          { role: "user", content: prompt }
        ],
        temperature: 0.7
      }
    )

    @last_api_response = response.dig("choices", 0, "message", "content").strip

    # Remove code block markers if present
    json_str = @last_api_response.gsub(/```(?:json)?/, '').strip

    begin
      recipes = JSON.parse(json_str)
      return recipes
    rescue JSON::ParserError => e
      puts "JSON Parsing Error: #{e.message}"
      puts "Response was: #{@last_api_response}"
      return []
    end
  end
end
