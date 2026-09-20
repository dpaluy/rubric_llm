# frozen_string_literal: true

require "test_helper"

class TestSystemOneSizeErrors < Minitest::Test
  include TestSetup

  Reply = Struct.new(:code, :body)

  def test_size_rejection_is_clear_not_retried_and_has_unknown_usage
    calls = 0
    transport = lambda do |**|
      calls += 1
      Reply.new("413", "state too large for size-test-key")
    end
    client = RubricLLM::SystemOne::Client.new(config:, transport:)
    question = RubricLLM::SystemOne::Question.noul("supported", instructions: "Is the answer supported?")

    error = assert_raises(RubricLLM::JudgeError) { client.call(state: "evidence", questions: [question]) }

    assert_equal 1, calls
    assert_match(/HTTP 413: too large/, error.message)
    assert_includes error.message, "reduce state/questions"
    assert_includes error.message, "[REDACTED]"
    refute_includes error.full_message, "size-test-key"
    assert_equal 1, client.usage_attempts.length
    assert_nil client.usage_attempts.first[:usage]
  end

  def test_size_rejection_falls_back_without_losing_the_reason_or_unknown_usage
    client = RubricLLM::SystemOne::Client.new(config:, transport: ->(**) { Reply.new("413", "state too large") })
    system_one = RubricLLM::Judges::SystemOne.new(config:, client:)
    cascade = RubricLLM::Judges::Cascade.new(config:, system_one:)
    metric = RubricLLM::Metrics::Faithfulness.new(judge: cascade)
    tokens = RubyLLMTokens.new(input: 7, output: 2)
    RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(response_tokens: tokens)

    result = metric.call(question: "Question?", answer: "Answer.", context: ["Evidence."])

    assert_in_delta 0.9, result[:score]
    assert result[:details][:escalated]
    assert_match(/too large/, result[:details][:escalation_reason])
    assert_match(/HTTP 413/, result[:details].dig(:system_one, :error))
    assert_equal 2, cascade.usage_attempts.length
    assert_nil RubricLLM::UsageSummary.new(cascade.usage_attempts).total
    assert_equal({ input_tokens: 7, output_tokens: 2 }, cascade.usage_attempts.last[:usage])
  end

  private

  def config
    RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "size-test-key", max_retries: 2)
  end
end
