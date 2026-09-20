# frozen_string_literal: true

require "uri"

module RubricLLM
  class Config
    BACKENDS = %i[chat system_one cascade].freeze

    attr_accessor :judge_model, :judge_provider, :temperature, :max_tokens, :custom_prompt,
                  :max_retries, :retry_base_delay, :concurrency, :judge_backend, :typesafe_api_key,
                  :decision_model, :typesafe_base_url, :typesafe_timeout, :cascade_confidence,
                  :cascade_noul_band, :cascade_policy, :typesafe_sentence_limit

    def initialize(judge_model: nil, judge_provider: nil, # rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
                   temperature: Float(ENV.fetch("RUBRIC_TEMPERATURE", "0.0")), max_tokens: nil,
                   custom_prompt: nil, max_retries: nil, retry_base_delay: nil, concurrency: nil,
                   judge_backend: nil, typesafe_api_key: nil, decision_model: nil, typesafe_base_url: nil,
                   typesafe_timeout: nil, cascade_confidence: nil, cascade_noul_band: nil,
                   cascade_policy: nil, typesafe_sentence_limit: nil, validate: false)
      @judge_model = judge_model || ENV.fetch("RUBRIC_JUDGE_MODEL", "gpt-4o")
      @judge_provider = (judge_provider || ENV.fetch("RUBRIC_JUDGE_PROVIDER", "openai")).to_sym
      @temperature = temperature
      @max_tokens = max_tokens || Integer(ENV.fetch("RUBRIC_MAX_TOKENS", "4096"))
      @custom_prompt = custom_prompt
      @max_retries = max_retries || Integer(ENV.fetch("RUBRIC_MAX_RETRIES", "2"))
      @retry_base_delay = retry_base_delay || Float(ENV.fetch("RUBRIC_RETRY_BASE_DELAY", "1.0"))
      @concurrency = concurrency || Integer(ENV.fetch("RUBRIC_CONCURRENCY", "1"))
      @judge_backend = (judge_backend || ENV.fetch("RUBRIC_JUDGE_BACKEND", "chat")).to_sym
      @typesafe_api_key = typesafe_api_key || ENV.fetch("TYPESAFE_API_KEY", nil)
      @decision_model = decision_model || ENV.fetch("RUBRIC_DECISION_MODEL", "jev-latest")
      @typesafe_base_url = typesafe_base_url || ENV.fetch("RUBRIC_TYPESAFE_BASE_URL", "https://api.typesafe.ai/v1")
      @typesafe_timeout = typesafe_timeout || Float(ENV.fetch("RUBRIC_TYPESAFE_TIMEOUT", "10"))
      @cascade_confidence = cascade_confidence || Float(ENV.fetch("RUBRIC_CASCADE_CONFIDENCE", "0.70"))
      @cascade_noul_band = cascade_noul_band || parse_band(ENV.fetch("RUBRIC_CASCADE_NOUL_BAND", "0.35,0.65"))
      @cascade_policy = cascade_policy
      @typesafe_sentence_limit = typesafe_sentence_limit || Integer(ENV.fetch("RUBRIC_TYPESAFE_SENTENCE_LIMIT", "40"))
      validate! if validate
    end

    def self.from_env
      new
    end

    def validate!
      validate_chat unless judge_backend == :system_one
      validate_max_retries
      validate_retry_base_delay
      validate_concurrency
      validate_typesafe
      validate_cascade
      self
    end

    def to_h
      {
        judge_model:, judge_provider:, temperature:, max_tokens:, custom_prompt:, max_retries:,
        retry_base_delay:, concurrency:, judge_backend:, typesafe_api_key:, decision_model:,
        typesafe_base_url:, typesafe_timeout:, cascade_confidence:, cascade_noul_band:,
        cascade_policy:, typesafe_sentence_limit:
      }
    end

    def inspect
      values = to_h.merge(typesafe_api_key: typesafe_api_key.nil? ? nil : "[REDACTED]")
      "#<#{self.class} #{values.inspect}>"
    end

    private

    def parse_band(value)
      lower, upper = value.split(",", 2).map { |item| Float(item) }
      lower..upper
    rescue NoMethodError, ArgumentError, TypeError
      raise ConfigurationError, "RUBRIC_CASCADE_NOUL_BAND must contain two comma-separated numbers"
    end

    def validate_chat
      validate_judge_model
      validate_judge_provider
      validate_temperature
      validate_max_tokens
    end

    def validate_judge_model
      return unless judge_model.nil? || judge_model.to_s.strip.empty?

      raise ConfigurationError, "judge_model must be a non-empty string"
    end

    def validate_judge_provider
      return if judge_provider.is_a?(Symbol)

      raise ConfigurationError, "judge_provider must be a symbol"
    end

    def validate_temperature
      return if temperature.nil? || (temperature.is_a?(Numeric) && temperature.between?(0.0, 2.0))

      raise ConfigurationError, "temperature must be nil or between 0.0 and 2.0"
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

    def validate_typesafe
      validate_typesafe_identity
      validate_typesafe_limits
      uri = URI.parse(typesafe_base_url.to_s)
      raise ConfigurationError, "typesafe_base_url must be an HTTP(S) URL" unless %w[http https].include?(uri.scheme) && uri.host
    rescue URI::InvalidURIError
      raise ConfigurationError, "typesafe_base_url must be an HTTP(S) URL"
    end

    def validate_typesafe_identity
      raise ConfigurationError, "judge_backend must be chat, system_one, or cascade" unless BACKENDS.include?(judge_backend)
      if %i[system_one cascade].include?(judge_backend) && (typesafe_api_key.nil? || typesafe_api_key.to_s.strip.empty?)
        raise ConfigurationError, "typesafe_api_key is required for #{judge_backend} backend"
      end
      return if decision_model.is_a?(String) && !decision_model.strip.empty?

      raise ConfigurationError, "decision_model must be a non-empty string"
    end

    def validate_typesafe_limits
      unless typesafe_timeout.is_a?(Numeric) && typesafe_timeout.positive?
        raise ConfigurationError, "typesafe_timeout must be a positive number"
      end
      return if typesafe_sentence_limit.is_a?(Integer) && typesafe_sentence_limit.positive?

      raise ConfigurationError, "typesafe_sentence_limit must be a positive integer"
    end

    def validate_cascade
      unless cascade_confidence.is_a?(Numeric) && cascade_confidence.between?(0.0, 1.0)
        raise ConfigurationError, "cascade_confidence must be between 0.0 and 1.0"
      end
      unless cascade_noul_band.is_a?(Range) && !cascade_noul_band.exclude_end? &&
             [cascade_noul_band.begin, cascade_noul_band.end].all? { |value| value.is_a?(Numeric) && value.between?(0.0, 1.0) } &&
             cascade_noul_band.begin <= cascade_noul_band.end
        raise ConfigurationError, "cascade_noul_band must be an inclusive range between 0.0 and 1.0"
      end
      return if cascade_policy.nil? || cascade_policy.respond_to?(:call)

      raise ConfigurationError, "cascade_policy must respond to call"
    end
  end
end
