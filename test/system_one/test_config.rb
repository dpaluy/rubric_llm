# frozen_string_literal: true

require "test_helper"

class TestSystemOneConfig < Minitest::Test
  ENV_KEYS = %w[
    RUBRIC_JUDGE_BACKEND RUBRIC_DECISION_MODEL RUBRIC_TYPESAFE_BASE_URL RUBRIC_TYPESAFE_TIMEOUT
    RUBRIC_CASCADE_CONFIDENCE RUBRIC_CASCADE_NOUL_BAND RUBRIC_TYPESAFE_SENTENCE_LIMIT TYPESAFE_API_KEY
  ].freeze

  def test_typesafe_defaults_preserve_chat_backend
    config = without_typesafe_env { RubricLLM::Config.new }

    assert_equal :chat, config.judge_backend
    assert_nil config.typesafe_api_key
    assert_equal "jev-latest", config.decision_model
    assert_equal "https://api.typesafe.ai/v1", config.typesafe_base_url
    assert_in_delta 10.0, config.typesafe_timeout
    assert_in_delta 0.70, config.cascade_confidence
    assert_equal(0.35..0.65, config.cascade_noul_band)
    assert_equal 40, config.typesafe_sentence_limit
    assert_nil config.cascade_policy
    assert_equal config, config.validate!
  end

  def test_reads_typesafe_environment
    with_env(
      "RUBRIC_JUDGE_BACKEND" => "cascade",
      "TYPESAFE_API_KEY" => "key",
      "RUBRIC_DECISION_MODEL" => "jev-1.13.0",
      "RUBRIC_TYPESAFE_BASE_URL" => "http://localhost:9292/v1",
      "RUBRIC_TYPESAFE_TIMEOUT" => "2.5",
      "RUBRIC_CASCADE_CONFIDENCE" => "0.8",
      "RUBRIC_CASCADE_NOUL_BAND" => "0.2,0.6",
      "RUBRIC_TYPESAFE_SENTENCE_LIMIT" => "25"
    ) do
      config = RubricLLM::Config.from_env

      assert_equal :cascade, config.judge_backend
      assert_equal "key", config.typesafe_api_key
      assert_equal "jev-1.13.0", config.decision_model
      assert_equal "http://localhost:9292/v1", config.typesafe_base_url
      assert_in_delta 2.5, config.typesafe_timeout
      assert_in_delta 0.8, config.cascade_confidence
      assert_equal(0.2..0.6, config.cascade_noul_band)
      assert_equal 25, config.typesafe_sentence_limit
      assert_equal config, config.validate!
    end
  end

  def test_system_one_does_not_require_chat_configuration
    config = RubricLLM::Config.new(judge_backend: :system_one, typesafe_api_key: "key")
    config.judge_model = nil
    config.judge_provider = "not-a-symbol"

    assert_equal config, config.validate!
  end

  def test_cascade_requires_valid_chat_configuration
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "key")
    config.judge_model = nil

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_system_one_and_cascade_require_api_key
    %i[system_one cascade].each do |backend|
      config = without_typesafe_env { RubricLLM::Config.new(judge_backend: backend) }

      error = assert_raises(RubricLLM::ConfigurationError) { config.validate! }
      assert_match(/typesafe_api_key is required/, error.message)
    end
  end

  def test_rejects_invalid_typesafe_settings
    invalid = {
      judge_backend: :unknown,
      decision_model: "",
      typesafe_base_url: "file:///tmp/api",
      typesafe_timeout: 0,
      cascade_confidence: 1.1,
      cascade_noul_band: 0.8..0.2,
      typesafe_sentence_limit: 0,
      cascade_policy: Object.new
    }

    invalid.each do |setting, value|
      config = RubricLLM::Config.new
      config.public_send("#{setting}=", value)
      assert_raises(RubricLLM::ConfigurationError, "expected #{setting} to be rejected") { config.validate! }
    end
  end

  def test_rejects_non_string_decision_model
    [123, { name: "jev-latest" }].each do |model|
      config = RubricLLM::Config.new(decision_model: model)

      error = assert_raises(RubricLLM::ConfigurationError) { config.validate! }
      assert_match(/non-empty string/, error.message)
    end
  end

  def test_to_h_preserves_secret_and_callable_for_configuration_copies
    policy = ->(_response) { true }
    config = RubricLLM::Config.new(typesafe_api_key: "top-secret", decision_model: "jev-1.13.0", cascade_policy: policy)
    copy = RubricLLM::Config.new(**config.to_h)

    assert_equal "top-secret", config.to_h[:typesafe_api_key]
    assert_equal "top-secret", copy.typesafe_api_key
    assert_equal "jev-1.13.0", copy.decision_model
    assert_equal "jev-1.13.0", config.to_h[:decision_model]
    assert_same policy, copy.cascade_policy
    refute_includes config.inspect, "top-secret"
    assert_includes config.inspect, "[REDACTED]"
  end

  private

  def without_typesafe_env(&)
    with_env(ENV_KEYS.to_h { |key| [key, nil] }, &)
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
