# frozen_string_literal: true

require "test_helper"

class TestJudge < Minitest::Test
  include TestSetup

  def test_parse_json_direct
    judge = RubricLLM::Judge.new(config: RubricLLM.config)
    result = judge.parse_json('{"score": 0.9, "reasoning": "good"}')

    assert_in_delta(0.9, result["score"])
  end

  def test_parse_json_code_fence
    judge = RubricLLM::Judge.new(config: RubricLLM.config)
    text = "Here is the result:\n```json\n{\"score\": 0.85}\n```"
    result = judge.parse_json(text)

    assert_in_delta(0.85, result["score"])
  end

  def test_parse_json_code_fence_no_lang
    judge = RubricLLM::Judge.new(config: RubricLLM.config)
    text = "```\n{\"score\": 0.7}\n```"
    result = judge.parse_json(text)

    assert_in_delta(0.7, result["score"])
  end

  def test_parse_json_nil_input
    judge = RubricLLM::Judge.new(config: RubricLLM.config)

    assert_nil judge.parse_json(nil)
  end

  def test_parse_json_empty_input
    judge = RubricLLM::Judge.new(config: RubricLLM.config)

    assert_nil judge.parse_json("")
  end

  def test_parse_json_unparseable
    judge = RubricLLM::Judge.new(config: RubricLLM.config)

    assert_nil judge.parse_json("This is not JSON at all")
  end

  def test_call_returns_parsed_json
    stub_judge_response('{"score": 0.95, "reasoning": "excellent"}')
    judge = RubricLLM::Judge.new(config: RubricLLM.config)
    result = judge.call(system_prompt: "test", user_prompt: "test")

    assert_in_delta(0.95, result["score"])
  end

  def test_call_appends_custom_prompt
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}')
    RubyLLMStub.fake_chat = chat

    config = RubricLLM::Config.new(custom_prompt: "Be strict about medical accuracy.")
    judge = RubricLLM::Judge.new(config:)
    judge.call(system_prompt: "You are a judge.", user_prompt: "Evaluate this.")

    assert_includes chat.last_system_prompt, "You are a judge."
    assert_includes chat.last_system_prompt, "Additional instructions:"
    assert_includes chat.last_system_prompt, "Be strict about medical accuracy."
  end

  def test_call_without_custom_prompt_passes_original
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}')
    RubyLLMStub.fake_chat = chat

    judge = RubricLLM::Judge.new(config: RubricLLM.config)
    judge.call(system_prompt: "You are a judge.", user_prompt: "Evaluate this.")

    assert_equal "You are a judge.", chat.last_system_prompt
  end

  def test_call_forwards_max_tokens
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}')
    RubyLLMStub.fake_chat = chat

    config = RubricLLM::Config.new(max_tokens: 256)
    judge = RubricLLM::Judge.new(config:)
    judge.call(system_prompt: "You are a judge.", user_prompt: "Evaluate this.")

    assert_equal({ max_tokens: 256 }, chat.last_params)
  end

  def test_call_retries_on_transient_failure
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}', fail_times: 1)
    RubyLLMStub.fake_chat = chat

    config = RubricLLM::Config.new(max_retries: 2, retry_base_delay: 0.0)
    judge = RubricLLM::Judge.new(config:)
    result = judge.call(system_prompt: "test", user_prompt: "test")

    assert_in_delta 0.9, result["score"]
    assert_equal 2, chat.call_count
  end

  def test_call_raises_after_exhausting_retries
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}', fail_times: 5)
    RubyLLMStub.fake_chat = chat

    config = RubricLLM::Config.new(max_retries: 2, retry_base_delay: 0.0)
    judge = RubricLLM::Judge.new(config:)

    error = assert_raises(RubricLLM::JudgeError) do
      judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_includes error.message, "transient failure"
    assert_equal 3, chat.call_count # initial + 2 retries
  end

  def test_call_no_retry_with_zero_max_retries
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.9}', fail_times: 1)
    RubyLLMStub.fake_chat = chat

    config = RubricLLM::Config.new(max_retries: 0, retry_base_delay: 0.0)
    judge = RubricLLM::Judge.new(config:)

    assert_raises(RubricLLM::JudgeError) do
      judge.call(system_prompt: "test", user_prompt: "test")
    end

    assert_equal 1, chat.call_count
  end
end
