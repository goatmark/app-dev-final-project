# app/services/openai_service.rb

class OpenaiService
  def initialize
    @client = OpenAI::Client.new(access_token: ENV['openai_key'])
  end

  def prompt_classify(message: "", chosen_model:  "gpt-4o")
    response = @client.chat(
      parameters: {
        model: chosen_model, # or another model like "gpt-3.5-turbo"
        messages: [
          { role: "system", content: "Return only 'note' or 'task' without quotes to best classify the message. Never respond otherwise." },
          { role: "user", content: message }
        ],
        temperature: 0 # Setting temperature to 0 for deterministic output
      }
    )

    # Extract the response text
    classification = response.dig("choices", 0, "message", "content").strip.downcase
    return(classification)
  end
end
