# app/services/openai_service.rb

class OpenaiService
  def initialize
    @client = OpenAI::Client.new
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
          Strictly always respond in  'YYYY-MM-DD' format without quotes."},
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
          { role: "system", content: "The message contains the 'body' of a Note to be stored in a database. Return only a proposed 'title' for the note. Do not return anything other than a title without quotes. Keep it salient and descriptive, not poetic."},
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
end
