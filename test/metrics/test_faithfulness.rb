# frozen_string_literal: true

require "test_helper"

class TestFaithfulness < Minitest::Test
  include TestSetup

  def test_returns_score_and_details
    stub_judge_response('{"score": 0.9, "claims": [{"claim": "Paris is capital", "supported": true}], "reasoning": "good"}')
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(
      question: "What is the capital of France?",
      answer: "The capital is Paris.",
      context: ["Paris is the capital of France."]
    )

    assert_in_delta 0.9, result[:score]
    assert result[:details][:claims]
    assert result[:details][:reasoning]
  end

  def test_handles_nil_judge_response
    stub_judge_response("")
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "q", answer: "a", context: ["c"])

    assert_nil result[:score]
  end

  def test_nil_without_context
    chat = RubyLLMStub::FakeChat.new
    RubyLLMStub.fake_chat = chat
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    result = metric.call(question: "q", answer: "a")

    assert_nil result[:score]
    assert_equal "No context provided", result[:details][:error]
    assert_nil chat.last_user_prompt
  end
end
