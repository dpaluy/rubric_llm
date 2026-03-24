# frozen_string_literal: true

require "test_helper"

class TestConfig < Minitest::Test
  include TestSetup

  def test_defaults
    config = RubricLLM::Config.new

    assert_equal "gpt-4o", config.judge_model
    assert_equal :openai, config.judge_provider
    assert_in_delta 0.0, config.temperature
    assert_equal 4096, config.max_tokens
    assert_nil config.custom_prompt
  end

  def test_to_h
    config = RubricLLM::Config.new
    hash = config.to_h

    assert_equal "gpt-4o", hash[:judge_model]
    assert_equal :openai, hash[:judge_provider]
  end

  def test_configure_block
    RubricLLM.configure do |c|
      c.judge_model = "claude-sonnet-4-6"
      c.judge_provider = :anthropic
    end

    assert_equal "claude-sonnet-4-6", RubricLLM.config.judge_model
    assert_equal :anthropic, RubricLLM.config.judge_provider
  end

  def test_reset_configuration
    RubricLLM.configure { |c| c.judge_model = "custom" }
    RubricLLM.reset_configuration!

    assert_equal "gpt-4o", RubricLLM.config.judge_model
  end

  def test_from_env
    config = RubricLLM::Config.from_env

    assert_equal "gpt-4o", config.judge_model
    assert_equal :openai, config.judge_provider
  end

  def test_keyword_arguments
    config = RubricLLM::Config.new(judge_model: "claude-haiku-4-5", judge_provider: :anthropic)

    assert_equal "claude-haiku-4-5", config.judge_model
    assert_equal :anthropic, config.judge_provider
  end

  def test_custom_prompt
    config = RubricLLM::Config.new(custom_prompt: "Be strict about medical accuracy.")

    assert_equal "Be strict about medical accuracy.", config.custom_prompt
  end

  def test_custom_prompt_via_configure
    RubricLLM.configure do |c|
      c.custom_prompt = "Evaluate for legal domain."
    end

    assert_equal "Evaluate for legal domain.", RubricLLM.config.custom_prompt
  end

  def test_custom_prompt_in_to_h
    config = RubricLLM::Config.new(custom_prompt: "test")

    assert_equal "test", config.to_h[:custom_prompt]
  end

  def test_new_config_options_defaults
    config = RubricLLM::Config.new

    assert_equal 2, config.max_retries
    assert_in_delta 1.0, config.retry_base_delay
    assert_equal 1, config.concurrency
  end

  def test_validate_passes_with_defaults
    config = RubricLLM::Config.new

    assert_equal config, config.validate!
  end

  def test_validate_rejects_empty_judge_model
    config = RubricLLM::Config.new
    config.judge_model = ""

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_nil_judge_model
    config = RubricLLM::Config.new
    config.judge_model = nil

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_non_symbol_provider
    config = RubricLLM::Config.new
    config.judge_provider = "openai"

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_negative_temperature
    config = RubricLLM::Config.new
    config.temperature = -1.0

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_temperature_above_two
    config = RubricLLM::Config.new
    config.temperature = 2.5

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_non_positive_max_tokens
    config = RubricLLM::Config.new
    config.max_tokens = 0

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_negative_max_retries
    config = RubricLLM::Config.new
    config.max_retries = -1

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_validate_rejects_non_positive_concurrency
    config = RubricLLM::Config.new
    config.concurrency = 0

    assert_raises(RubricLLM::ConfigurationError) { config.validate! }
  end

  def test_configure_validates_eagerly
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM.configure { |c| c.temperature = -5.0 }
    end
  end

  def test_configure_rolls_back_invalid_changes
    RubricLLM.configure do |c|
      c.judge_model = "claude-sonnet-4-6"
      c.temperature = 0.3
    end
    original_config = RubricLLM.config.to_h

    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM.configure { |c| c.temperature = -5.0 }
    end

    assert_equal original_config, RubricLLM.config.to_h
  end
end
