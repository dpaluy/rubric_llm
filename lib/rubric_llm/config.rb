# frozen_string_literal: true

module RubricLLM
  class Config
    attr_accessor :judge_model, :judge_provider, :temperature, :max_tokens, :custom_prompt,
                  :max_retries, :retry_base_delay, :concurrency

    def initialize(judge_model: nil, judge_provider: nil, temperature: nil, max_tokens: nil, # rubocop:disable Metrics/ParameterLists
                   custom_prompt: nil, max_retries: nil, retry_base_delay: nil, concurrency: nil, validate: false)
      @judge_model = judge_model || ENV.fetch("RUBRIC_JUDGE_MODEL", "gpt-4o")
      @judge_provider = (judge_provider || ENV.fetch("RUBRIC_JUDGE_PROVIDER", "openai")).to_sym
      @temperature = temperature || Float(ENV.fetch("RUBRIC_TEMPERATURE", "0.0"))
      @max_tokens = max_tokens || Integer(ENV.fetch("RUBRIC_MAX_TOKENS", "4096"))
      @custom_prompt = custom_prompt
      @max_retries = max_retries || Integer(ENV.fetch("RUBRIC_MAX_RETRIES", "2"))
      @retry_base_delay = retry_base_delay || Float(ENV.fetch("RUBRIC_RETRY_BASE_DELAY", "1.0"))
      @concurrency = concurrency || Integer(ENV.fetch("RUBRIC_CONCURRENCY", "1"))
      validate! if validate
    end

    def self.from_env
      new
    end

    def validate!
      validate_judge_model
      validate_judge_provider
      validate_temperature
      validate_max_tokens
      validate_max_retries
      validate_retry_base_delay
      validate_concurrency
      self
    end

    def to_h
      {
        judge_model:,
        judge_provider:,
        temperature:,
        max_tokens:,
        custom_prompt:,
        max_retries:,
        retry_base_delay:,
        concurrency:
      }
    end

    private

    def validate_judge_model
      return unless judge_model.nil? || judge_model.to_s.strip.empty?

      raise ConfigurationError, "judge_model must be a non-empty string"
    end

    def validate_judge_provider
      return if judge_provider.is_a?(Symbol)

      raise ConfigurationError, "judge_provider must be a symbol"
    end

    def validate_temperature
      return if temperature.is_a?(Numeric) && temperature.between?(0.0, 2.0)

      raise ConfigurationError, "temperature must be between 0.0 and 2.0"
    end

    def validate_max_tokens
      return if max_tokens.is_a?(Integer) && max_tokens.positive?

      raise ConfigurationError, "max_tokens must be a positive integer"
    end

    def validate_max_retries
      return if max_retries.is_a?(Integer) && max_retries >= 0

      raise ConfigurationError, "max_retries must be a non-negative integer"
    end

    def validate_retry_base_delay
      return if retry_base_delay.is_a?(Numeric) && retry_base_delay >= 0

      raise ConfigurationError, "retry_base_delay must be a non-negative number"
    end

    def validate_concurrency
      return if concurrency.is_a?(Integer) && concurrency.positive?

      raise ConfigurationError, "concurrency must be a positive integer"
    end
  end
end
