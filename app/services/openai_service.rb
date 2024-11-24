# app/services/openai_service.rb

class OpenaiService
  def initialize
    @client = OpenAI::Client.new
  end

  def transcribe_audio(audio_file_path)
    response = @client.audio.transcribe(
      parameters: {
        model: "whisper-1",
        file: File.open(audio_file_path, "rb")
      }
    )
    transcription = response['text']
    return transcription
  end

  def prompt_classify(message: "", chosen_model:  "gpt-4o-mini")
    response = @client.chat(
      parameters: {
        model: chosen_model, 
        messages: [
          { role: "system", content: "Return only 'note' or 'task' without quotes to best classify the message (reminders are tasks). Never respond otherwise."},
          { role: "user", content: message }
        ],
        temperature: 0 # Setting temperature to 0 for deterministic output
      }
    )

    # Extract the response text
    classification = response.dig("choices", 0, "message", "content").strip.downcase
    return(classification)
  end

  def prompt_extract_task(message: "", chosen_model:  "gpt-4o-mini")
    response = @client.chat(
      parameters: {
        model: chosen_model, 
        messages: [
          { role: "system", content: "Extract only a summary of the task as if it were to be put on a To-Do list or Kanban board. 
          Do not use any leading bullet/hyphen characters.
          If a deadline is specified, do not include it in the task summary; it will be extracted separately."},
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )

    # Extract the response text
    task = response.dig("choices", 0, "message", "content").strip
    return(task)
  end

  def prompt_extract_deadline(message: "", chosen_model:  "gpt-4o-mini")
    today = Date.today
    tomorrow = today + 1
    dow = today.strftime('%A')
    todays_date=today.strftime('%Y-%m-%d')
    tomorrows_date=tomorrow.strftime('%Y-%m-%d')
    response = @client.chat(
      parameters: {
        model: chosen_model, 
        messages: [
          { role: "system", content: "Return only the deadline knowing today is #{dow}, #{todays_date}.
          (e.g. if something says it's due Tuesday, assume it's due the first Tuesday after #{todays_date}).
          If no deadline specified, return #{tomorrows_date}. 
          If something is to be done 'today', return #{todays_date}.
          If something is due 'next week', assume a 7 day deadline from today. 
          If something is due 'next month', assume a deadline a full calendar month from today.
          Strictly always respond in  'YYYY-MM-DD' format without quotes.
          Assume something to be done 'end of the week' is due Friday."},
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    # Extract the response text
    deadline = response.dig("choices", 0, "message", "content").strip
    return(deadline)
  end

  def prompt_extract_action_date(message: "", chosen_model:  "gpt-4o-mini")
    today = Date.today
    tomorrow = today + 1
    todays_date=today.strftime('%Y-%m-%d')
    tomorrows_date=tomorrow.strftime('%Y-%m-%d')
    response = @client.chat(
      parameters: {
        model: chosen_model, 
        messages: [
          { role: "system", content: "Today's date is #{todays_date}.
          If the prompt contains information about a 'reminder', e.g. 'remind me in 2 days,' return only the corresponding date in '%Y-%m-%d' format, or YYYY-MM-DD format.
          Do not confuse this with the deadline. If a prompt says 'Send out an email in 2 days,' you should return #{todays_date}.
          If a prompt says 'Remind me tomorrow to send an email in 2 days,' you should return only #{tomorrows_date}.
          If the prompt does nto contain information about a reminder, return only #{todays_date}.
          Only ever return a date.
          Assume something to be done 'end of the week' is due Friday."},
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    # Extract the response text
    deadline = response.dig("choices", 0, "message", "content").strip
    return(deadline)
  end

  def prompt_note_title(message: "", chosen_model:  "gpt-4o-mini")
    response = @client.chat(
      parameters: {
        model: chosen_model, 
        messages: [
          { role: "system", content: "The message contains the 'body' of a Note to be stored in a database. Return only a proposed 'title' for the note. Do not return anything other than a title without quotes. Keep it concise, salient and descriptive, not poetic. Colons are strictly not allowed."},
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    # Extract the response text
    title = response.dig("choices", 0, "message", "content").strip
    return(title)
  end

  def prompt_note_summary(message: "", chosen_model:  "gpt-4o-mini")
    response = @client.chat(
      parameters: {
        model: chosen_model, 
        messages: [
          { role: "system", content: "Context: You are responsible for parsing elements of a dictation.
          Your job is extract just the 'note' part of the message given to you, excluding any commands given to the dictation app.
          In other words, if receiving something that says 'Make a note that I need to...', return 'I need to...' onwards.
          Return the full note. Do NOT summarize, paraphrase, or copy edit. You may only make minor tweaks to address filler words (ums/likes), misspoken words, or fractured sentences. Do NOT summarize. Do NOT attempt to improve quality of writing beyond specification."},
          { role: "user", content: message }
        ],
        temperature: 0.7
      }
    )
    # Extract the response text
    body = response.dig("choices", 0, "message", "content").strip
    return(body)
  end

  # Function to find the best match using OpenAI
  def find_best_match(search_term:, options:, chosen_model: 'gpt-3.5-turbo')
    options_list = options.join("\n")
    prompt = <<~PROMPT
      Given the search term "#{search_term}", find the best match from the following options:
      #{options_list}
      Return only the exact text of the best matching option, or "No match" if none is suitable.
    PROMPT

    response = @client.chat(
      parameters: {
        model: chosen_model,
        messages: [
          { role: "user", content: prompt }
        ],
        temperature: 0
      }
    )

    result = response.dig("choices", 0, "message", "content").strip
    return nil if result.downcase == "no match"
    return result
  end

  # Method to extract related entities with their types
  def extract_related_entities(message:, chosen_model: 'gpt-3.5-turbo')
    prompt = <<~PROMPT
      From the following message, extract all names of people, classes (courses), or companies mentioned that could be relations in a Notion database.
      For each entity, identify its type as one of: "person", "class", or "company".
      Return the results in JSON format as an array of objects with "name" and "type" keys.
      Example:
      [
        {"name": "Mitch Matthews", "type": "person"},
        {"name": "North Face", "type": "company"}
      ]
      Message: "#{message}"
    PROMPT

    response = @client.chat(
      parameters: {
        model: chosen_model,
        messages: [
          { role: "user", content: prompt }
        ],
        temperature: 0.7
      }
    )

    result = response.dig("choices", 0, "message", "content").strip

    begin
      entities = JSON.parse(result)
      return entities
    rescue JSON::ParserError
      return []
    end
  end
end
