# frozen_string_literal: true

require "test_helper"

class TestThinkingEffort < Minitest::Test
  include TestSetup

  def test_defaults_to_nil
    with_thinking_effort_env(nil) do
      assert_nil RubricLLM::Config.new.thinking_effort
    end
  end

  def test_reads_environment
    with_thinking_effort_env("high") do
      assert_equal "high", RubricLLM::Config.from_env.thinking_effort
      assert_equal :low, RubricLLM::Config.new(thinking_effort: :low).thinking_effort
      assert_nil RubricLLM::Config.new(thinking_effort: nil).thinking_effort
    end
  end

  def test_survives_configure_and_to_h
    RubricLLM.configure { |config| config.thinking_effort = :high }
    RubricLLM.configure { |config| config.judge_model = "custom" }
    copy = RubricLLM::Config.new(**RubricLLM.config.to_h)

    assert_equal :high, copy.thinking_effort
  end

  def test_nil_survives_roundtrip_with_environment
    with_thinking_effort_env("high") do
      config = RubricLLM::Config.new(thinking_effort: nil)

      assert_nil RubricLLM::Config.new(**config.to_h).thinking_effort
    end
  end

  def test_validate_accepts_model_specific_effort
    [nil, :low, "medium", :high, :xhigh, "max", :none, :future_effort].each do |effort|
      config = RubricLLM::Config.new(thinking_effort: effort)

      assert_same config, config.validate!
    end
  end

  def test_validate_rejects_invalid_effort
    ["", " ", :"", false, 1, []].each do |effort|
      config = RubricLLM::Config.new(thinking_effort: effort)

      error = assert_raises(RubricLLM::ConfigurationError) { config.validate! }

      assert_equal "thinking_effort must be nil or a non-empty string or symbol", error.message
    end
  end

  def test_call_forwards_effort
    [:high, "max"].each do |effort|
      chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}')
      RubyLLMStub.fake_chat = chat
      config = RubricLLM::Config.new(thinking_effort: effort)

      result = RubricLLM::Judge.new(config:).call(system_prompt: "test", user_prompt: "test")

      assert_equal({ enabled: true, effort: }, chat.last_thinking)
      assert_in_delta 0.9, result["score"]
    end
  end

  def test_call_does_not_configure_thinking_when_effort_is_nil
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}')
    RubyLLMStub.fake_chat = chat
    config = RubricLLM::Config.new(thinking_effort: nil)

    RubricLLM::Judge.new(config:).call(system_prompt: "test", user_prompt: "test")

    assert_nil chat.last_thinking
  end

  def test_evaluation_preserves_effort_with_custom_prompt
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9, "reasoning": "relevant"}')
    RubyLLMStub.fake_chat = chat

    with_thinking_effort_env("high") do
      result = RubricLLM.evaluate(
        question: "What is Ruby?", answer: "A programming language",
        metrics: [RubricLLM::Metrics::Relevance],
        config: RubricLLM::Config.from_env, custom_prompt: "Be strict."
      )

      assert_equal({ enabled: true, effort: "high" }, chat.last_thinking)
      assert_in_delta 0.9, result.scores[:relevance]
    end
  end

  private

  def with_thinking_effort_env(value)
    previous = ENV.fetch("RUBRIC_THINKING_EFFORT", nil)
    value.nil? ? ENV.delete("RUBRIC_THINKING_EFFORT") : ENV["RUBRIC_THINKING_EFFORT"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("RUBRIC_THINKING_EFFORT") : ENV["RUBRIC_THINKING_EFFORT"] = previous
  end
end
