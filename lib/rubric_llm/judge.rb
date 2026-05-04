# frozen_string_literal: true

require "json"

module RubricLLM
  class Judge
    METRIC_RESPONSE_SCHEMA = {
      name: "rubric_llm_metric_response",
      strict: false,
      schema: {
        type: "object",
        properties: {
          score: { type: "number", minimum: 0.0, maximum: 1.0 },
          reasoning: { type: "string" },
          claims: { type: "array", items: { type: "object" } },
          context_scores: { type: "array", items: { type: "object" } },
          covered_facts: { type: "array", items: { type: "object" } },
          discrepancies: { type: "array", items: { type: "object" } }
        },
        required: ["score"],
        additionalProperties: true
      }
    }.freeze

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
        apply_response_schema(chat)

        full_system_prompt = build_system_prompt(system_prompt)
        chat.with_instructions(full_system_prompt)
        response = chat.ask(user_prompt)
        validate_response!(parse_json(response.content))
      rescue StandardError => e
        if attempts > config.max_retries
          raise e if e.is_a?(JudgeError)

          raise JudgeError, "Judge call failed: #{e.message}"
        end

        sleep(config.retry_base_delay * (2**(attempts - 1)))
        retry
      end
    end

    # Parse JSON from LLM output with multiple strategies:
    # 1. Direct JSON.parse
    # 2. Extract from markdown code fence
    # 3. Raise JudgeError for malformed output
    def parse_json(text)
      raise JudgeError, "Judge response was empty" if text.nil? || text.strip.empty?

      JSON.parse(text)
    rescue JSON::ParserError => e
      if (match = text.match(/```(?:json)?\s*\n?(.*?)\n?\s*```/m))
        begin
          return JSON.parse(match[1])
        rescue JSON::ParserError => e
          raise JudgeError, "Judge response code fence was not valid JSON: #{e.message}"
        end
      end

      raise JudgeError, "Judge response was not valid JSON: #{e.message}"
    end

    private

    def apply_response_schema(chat)
      return chat unless chat.respond_to?(:with_schema)
      return chat unless structured_output_supported?(chat)

      chat.with_schema(METRIC_RESPONSE_SCHEMA)
    end

    def structured_output_supported?(chat)
      return true unless chat.respond_to?(:model)
      return true unless chat.model.respond_to?(:structured_output?)

      chat.model.structured_output?
    end

    def validate_response!(response)
      raise JudgeError, "Judge response must be a JSON object" unless response.is_a?(Hash)
      raise JudgeError, "Judge response missing required score" unless response.key?("score")

      score = parse_score(response["score"])
      raise JudgeError, "Judge response score must be between 0.0 and 1.0" unless score.finite? && score.between?(0.0, 1.0)

      response
    end

    def parse_score(score)
      Float(score)
    rescue ArgumentError, TypeError
      raise JudgeError, "Judge response score must be numeric"
    end

    def build_system_prompt(base_prompt)
      return base_prompt unless config.custom_prompt

      "#{base_prompt}\n\nAdditional instructions:\n#{config.custom_prompt}"
    end
  end
end
