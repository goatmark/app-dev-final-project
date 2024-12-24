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
      - wordle
      - restaurant
      - people_update
    Each of these classifiers will lead to a set of appropriate events. Key examples:
      - Suggesting items to add to the shopping list should update the 'ingredient' database such that the 'Shopping List' field is true. A message comprising a single ingredient, household item, or foodstuff should also certainly return an 'ingredient'.
      - Suggesting an intention to make or cook something should be treated as a 'recipe'.
      - Mentioning scores or games played in Wordle should be classified as 'wordle'. A message like '2-3 Mark' or 'My girlfriend beat me today 3-4', or even just '5-5' falls into the 'wordle' category. 
      - Recommending or mentioning a restaurant should be classified as 'restaurant'.
      - Suggesting something is a 'task' will proceed to extract its start date and deadline (where applicable).
      - Saying 'I should read more about nihilism' will create an entry in the 'recommendation' DB with 'nihilism' as the title.
      - A 'people_update' is when the user provides a factual update or new information specifically about a single person. 
          Examples: 
          - 'David told me that he is going to Bali tomorrow' -> 'people_update' 
          - 'Goliath really liked Le Creuset ceramics' -> 'people_update'
          - 'William is allergic to bees' -> 'people_update'
          - 'Paul told me that he really does not like Picasso' -> 'people_update' (this is still a people update; two people are mentioned - Paul and Picasso - but there is only one subject and Picasso is an object relative to the main subject. This is a factual update about one person)
          Things that should be classified as 'note' rather than 'people_update':
          - A note about two people should be referenced as a note, e.g.
            'I had lunch today with Anna and Bob' -> 'note'
          - A note referencing one person that is more about a general subject, rather than personal information updates, should be a note:
            'I had a conversation with Anna. She provided an interesting insight: that the Roomba is actually an analytical device' is a 'note'. This is not factual information about Anna, it is a general note.
      - Anything that does not neatly meet any of the categories above should default to 'note'.
    Return only the classification, in the singular, with NO other text and without quotes.

    Examples:
      'Wine' -> 'ingredient'
      'Tomatoes, parsley, mint, sumac' -> 'ingredient'
      'I need to add spring onions, lemon, and mint to the shopping list' -> 'ingredient'
      'Tabbouleh' -> 'recipe'
      'I want to make fattoush' -> 'recipe'
      '5-5' -> 'wordle'
      '3-4 Lorna' -> 'wordle'
      'The professor recommended I check out the restaurant Next in Chicago' -> 'restaurant'
      'Remind me tomorrow that I need to take out the trash by Friday' -> 'task'
      'The professor recommended I check out some of the works of Peter Thiel' -> 'recommendation'

    PROMPT
  
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: prompt },
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
        model: "gpt-4o-mini",
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
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "Extract only the identified piece of media (book title, article title, etc). Only include the title. Do not include any other text. Do not include author name or any other information (unless the recommendation lacks a specific name or includes something like 'Books by David Wright' or 'Philosophy of Nietzsche' or 'Dr. Oz's Podcast' - in which case, return a helpful description that accurately captures the recommendation)." },
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
        model: "gpt-4o-mini",
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
        model: "gpt-4o-mini",
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
        model: "gpt-4o-mini",
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
        model: "gpt-4o-mini",
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

  def extract_note_body(message:, type: "note")
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "Context: You are responsible for parsing elements of a dictation. Your job is to extract just the 'note' part of the message given to you, excluding any commands given to the dictation app. In other words, if receiving something that says 'Make a note that I need to...', return 'I need to...' onwards. 
          
              Your job is to return the full note. Key instructions:
              - Do NOT summarize, paraphrase, or copy edit. Your goal is to extract, not to summarize
              - You may only make minor tweaks to the note body, such as  filler words (ums/likes), misspoken words, or fractured sentences.
              - Do NOT attempt to improve the quality of writing beyond specification.
              - Your output should mirror the original input closely, with only minor changes as specified above with no other changes.
              If #{type} == 'note', ignore all subsequent instructions. If #{type} == 'people_update' do the following:
              - Remove references to the person's name
              - Extract only meaningful content 
              Example:
              - 'I just learned that Albert Einstein couldn't put a T-shirt on his own' -> 'Couldn't put a T-shirt on his own'
              - 'Lorna really liked the brand Le Creuset' -> 'Likes Le Creuset'"},
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    body = response.dig("choices", 0, "message", "content").strip
    return body
  end

  def extract_related_entities(message:, default: true)
    if default
      prompt = <<~PROMPT
        From the following message, extract all specific names of people, specific classes (courses offered at Booth), or companies mentioned that could be relations in a Notion database.
        Do not include generic terms or groups like "MBA students" or "students".
        Do not include fictional characters including Gods, Titans, or other characters.
        For each entity, identify its type as one of: "person", "class", or "company".
        Return the results in JSON format as an array of objects with "name" and "type" keys.
        **Do not include any code block markers, triple backticks, or any additional text before or after the JSON.**
        Example:
        [
          {"name": "Mark Khoury", "type": "person"},
          {"name": "Digital Marketing Lab", "type": "class"},
          {"name": "North Face", "type": "company"}
        ]
        Message: "#{message}"
      PROMPT
    else
      prompt = <<~PROMPT
        From the following message, extract all specific names of people, and classify them as either "recommender" or "author".

        - Do not include generic terms or groups like "MBA students" or "students".
        - Return the results in JSON format as an array of objects with "name" and "type" keys.
        - **Do not include any code block markers, triple backticks, or any additional text before or after the JSON.**

        Example:
        [
          {"name": "Lydia Wang", "type": "recommender"},
          {"name": "Albert Einstein", "type": "author"}
        ]
        Message: "#{message}"
      PROMPT
    end

    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
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
        model: "gpt-4o-mini",
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
      - Do NOT include any measurement or container units. As an example, never return a "name" of 'Jar of Cumin'; ignore 'jar' and only ever return a name of 'Cumin' in this example.
      - Do not include any code block markers or additional text.
      - If the message states to remove an item from the shopping list, add a quantity of -1.
      - Examine the message holistically, as it originates from a dictation and may be unintentionally redundant. E.g. if the message says 'add mint, and parsley and, wait, do I need tomatoes? Yes, that is right - pkay, so parsley, mint, and 4 tomatoes', you will want to add 1 parsley, 1 mint, and 4 tomatoes, per the JSON specifications below.

      Key preferences / associations (in all cases unless specified otherwise):
      - Assume 'Onions' refers to 'Yellow Onion'
      - Assume 'Wine' refers to 'Red Wine'
      - Assume 'Chocolate' refers to 'Dark Chocolate'
      - Assume 'Garlic' refers to 'Garlic Cloves' unless a whole unit is specified, in which case name should be 'Garlic Bulb'

      Example:
      [
        {"name": "Yellow Onion", "quantity": 1},
        {"name": "Garlic Cloves", "quantity": 2},
        {"name": "Cinnamon", "quantity": 1},
        {"name": "Parsley", "quantity": 1}
      ]

      Message: "#{message}"
    PROMPT

    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
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
        model: "gpt-4o-mini",
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

  def extract_wordle_scores(message:)
    prompt = <<~PROMPT
      From the following message, extract the Wordle scores for 'Mark' and 'Lorna'.
      - Wordle is a game where a lower score is better. Be VERY careful how you interpret scores for each person as the user may make mistakes:
        - If speaker says "I beat Lorna 4-3 today," the winner is the one with the lower score (Mark won, so his score is 3).
        - If speaker says "I beat Lorna by 2 points, with a score of 4" that means Mark scored 4 and Lorna scored 6 points.
        - If speaker says "2-3 Lorna", it means Lorna won Wordle with a score of 2 and Mark lost with a score of 3.
      - The message may state who beat whom, or that there was a tie.
      - Return the results in JSON format as an object with keys 'Mark' and 'Lorna', and their respective scores as integers.
      - Do not include any code block markers or additional text.
      - In the absence of any other clues, the first-person speaker is 'Mark' and his opponent (girlfriend) is 'Lorna'
  
      Examples:
      Message: "Lorna beat me 3-4"
      Output:
      {"Mark": 4, "Lorna": 3}
  
      Message: "We both tied at Wordle with a score of 2"
      Output:
      {"Mark": 2, "Lorna": 2}
  
      Message: "I beat my girlfriend at Wordle 3-6"
      Output:
      {"Mark": 3, "Lorna": 6}
  
      Message: "#{message}"
    PROMPT
  
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7
      }
    )
  
    json_str = response.dig("choices", 0, "message", "content").strip
    json_str = json_str.gsub(/```(?:json)?/, '').strip
  
    begin
      scores = JSON.parse(json_str)
      return scores
    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parsing Error: #{e.message}"
      Rails.logger.error "Response was: #{json_str}"
      return {}
    end
  end

  def extract_restaurant_info(message:)
    prompt = <<~PROMPT
      From the following message, extract the name of the restaurant being recommended and the name of the person who recommended it.
      - Return the result in JSON format as an object with keys "restaurant_name" and "recommender_name".
      - If no recommender is specified, you can assume the recommender is 'Mark' (i.e., yourself).
      - Do not include any code block markers or additional text.
  
      Example:
      Message: "My friend John suggested we try the new Italian place called Luigi's."
      Output:
      {"restaurant_name": "Luigi's", "recommender_name": "John"}
  
      Message: "I want to check out that sushi place downtown."
      Output:
      {"restaurant_name": "That sushi place downtown", "recommender_name": "Mark"}
  
      Message: "#{message}"
    PROMPT
  
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7
      }
    )
  
    json_str = response.dig("choices", 0, "message", "content").strip
    json_str = json_str.gsub(/```(?:json)?/, '').strip
  
    begin
      info = JSON.parse(json_str)
      return info
    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parsing Error: #{e.message}"
      Rails.logger.error "Response was: #{json_str}"
      return {}
    end
  end

  def extract_idea_title_and_body(message:)
    prompt = <<~PROMPT
      From the following message, extract the idea''s title and body.
      - The title should be a concise summary of the idea.
      - The body should be the full description of the idea.
      - Return the result in JSON format with keys "title" and "body".
      - Do not include any code block markers or additional text.
  
      Example:
      Message: "I just thought of a new app that helps people find parking spots in crowded cities."
      Output:
      {"title": "Parking Spot Finder App", "body": "I just thought of a new app that helps people find parking spots in crowded cities."}
  
      Message: "#{message}"
    PROMPT
  
    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.7
      }
    )
  
    json_str = response.dig("choices", 0, "message", "content").strip
    json_str = json_str.gsub(/```(?:json)?/, '').strip
  
    begin
      idea = JSON.parse(json_str)
      return idea
    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parsing Error: #{e.message}"
      Rails.logger.error "Response was: #{json_str}"
      return {}
    end
  end

  def generate_task_plan(task_summary:, gathered_info:)
    prompt = construct_plan_prompt(task_summary: task_summary, gathered_info: gathered_info)

    # Log the prompt being sent to OpenAI
    Rails.logger.info "OpenAI Prompt for Task Plan:\n#{prompt}"

    response = @client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "You are an assistant that helps in planning tasks by leveraging all available information from associated entities and related notes. Provide a detailed plan of action to accomplish the task effectively." },
          { role: "user", content: prompt }
        ],
        temperature: 0.7,
        max_tokens: 500
      }
    )

    plan = response.dig("choices", 0, "message", "content").strip

    # Log the response received from OpenAI
    Rails.logger.info "OpenAI Response for Task Plan:\n#{plan}"

    return plan
  end

  private

  # Helper method to construct the prompt for plan generation
  def construct_plan_prompt(task_summary:, gathered_info:)
    info_text = gathered_info.map do |key, value|
      "#{key}:\n#{value}\n"
    end.join("\n")

    prompt = <<~PROMPT
      Task Summary:
      #{task_summary}

      Gathered Information:
      #{info_text}

      Based on the above information, provide the best possible plan of attack to accomplish the task. The plan should include actionable steps, considerations, and any relevant resources or strategies.
    PROMPT

    prompt
  end
end
