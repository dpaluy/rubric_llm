# frozen_string_literal: true

require "json"

module RubricLLM
  class Judge
    attr_reader :config

    def initialize(config:)
      @config = config
    end

    # Send a prompt to the judge LLM and return the parsed JSON response.
    # Retries transient failures with exponential backoff.
    def call(system_prompt:, user_prompt:)
      config.validate!
      attempts = 0
      begin
        attempts += 1
        chat = RubyLLM.chat(model: config.judge_model, provider: config.judge_provider)
        chat.with_temperature(config.temperature)
        chat.with_params(max_tokens: config.max_tokens)

        full_system_prompt = build_system_prompt(system_prompt)
        response = chat.ask(user_prompt, with: full_system_prompt)
        parse_json(response.content)
      rescue StandardError => e
        raise JudgeError, "Judge call failed: #{e.message}" if attempts > config.max_retries

        sleep(config.retry_base_delay * (2**(attempts - 1)))
        retry
      end
    end

    # Parse JSON from LLM output with multiple strategies:
    # 1. Direct JSON.parse
    # 2. Extract from markdown code fence
    # 3. Return nil (never raises)
    def parse_json(text)
      return nil if text.nil? || text.strip.empty?

      # Try direct parse
      JSON.parse(text)
    rescue JSON::ParserError
      # Try extracting from code fence
      if (match = text.match(/```(?:json)?\s*\n?(.*?)\n?\s*```/m))
        begin
          JSON.parse(match[1])
        rescue JSON::ParserError
          nil
        end
      end
    end

    private

    def build_system_prompt(base_prompt)
      return base_prompt unless config.custom_prompt

      "#{base_prompt}\n\nAdditional instructions:\n#{config.custom_prompt}"
    end
  end
end
