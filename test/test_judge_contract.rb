# frozen_string_literal: true

require "test_helper"

class TestJudgeContract < Minitest::Test
  include TestSetup

  def test_call_applies_metric_response_schema
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.95, "reasoning": "excellent"}')
    RubyLLMStub.fake_chat = chat

    result = judge.call(system_prompt: "test", user_prompt: "test")

    assert_in_delta(0.95, result["score"])
    assert_equal RubricLLM::Judge::METRIC_RESPONSE_SCHEMA, chat.last_schema
  end

  def test_call_raises_for_malformed_json
    chat = RubyLLMStub::FakeChat.new(response_content: "This is not JSON")
    RubyLLMStub.fake_chat = chat

    error = assert_raises(RubricLLM::JudgeError) do
      judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_includes error.message, "not valid JSON"
    assert_equal 1, chat.call_count
  end

  def test_call_retries_judge_contract_failures
    chat = RubyLLMStub::FakeChat.new(response_content: "This is not JSON")
    RubyLLMStub.fake_chat = chat

    retrying_judge = RubricLLM::Judge.new(config: RubricLLM::Config.new(max_retries: 1, retry_base_delay: 0.0))

    assert_raises(RubricLLM::JudgeError) do
      retrying_judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_equal 2, chat.call_count
  end

  def test_call_raises_for_missing_score
    chat = RubyLLMStub::FakeChat.new(response_content: '{"reasoning": "missing"}')
    RubyLLMStub.fake_chat = chat

    error = assert_raises(RubricLLM::JudgeError) do
      judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_includes error.message, "missing required score"
  end

  def test_call_raises_for_non_numeric_score
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": "excellent", "reasoning": "bad score"}')
    RubyLLMStub.fake_chat = chat

    error = assert_raises(RubricLLM::JudgeError) do
      judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_includes error.message, "must be numeric"
  end

  def test_call_raises_for_out_of_range_score
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 1.1, "reasoning": "too high"}')
    RubyLLMStub.fake_chat = chat

    error = assert_raises(RubricLLM::JudgeError) do
      judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_includes error.message, "between 0.0 and 1.0"
  end

  private

  def judge
    RubricLLM::Judge.new(config: RubricLLM::Config.new(max_retries: 0, retry_base_delay: 0.0))
  end
end
