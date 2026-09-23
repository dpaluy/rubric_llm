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

    assert_in_delta 1.0, result[:score]
    assert result[:details][:claims]
    assert result[:details][:reasoning]
  end

  def test_score_uses_supported_claims_not_judge_score
    stub_judge_response('{"score": 1.0, "claims": ' \
                        '[{"claim": "a", "supported": true}, {"claim": "b", "supported": false}], ' \
                        '"reasoning": "one unsupported"}')
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    result = metric.call(question: "q", answer: "a and b", context: ["a"])

    assert_in_delta 0.5, result[:score]
  end

  def test_rejects_missing_claims
    stub_judge_response('{"score": 0.9, "reasoning": "good"}')
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a", context: ["a"]) }
  end

  def test_rejects_empty_claims
    stub_judge_response('{"score": 1.0, "claims": [], "reasoning": "no factual claims"}')
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    error = assert_raises(RubricLLM::JudgeError) do
      metric.call(question: "q", answer: "I don't know", context: ["a"])
    end
    assert_includes error.message, "invalid claims"
  end

  def test_evaluate_returns_nil_for_empty_claims
    stub_judge_response('{"score": 1.0, "claims": [], "reasoning": "no factual claims"}')
    result = RubricLLM.evaluate(
      question: "q", answer: "I don't know", context: ["a"], metrics: [RubricLLM::Metrics::Faithfulness]
    )

    assert_nil result.scores[:faithfulness]
    assert_includes result.errors[:faithfulness], "invalid claims"
    refute_predicate result, :pass?
  end

  def test_evaluate_reports_invalid_metric_evidence
    stub_judge_response('{"score": 1.0, "reasoning": "supported"}')
    result = RubricLLM.evaluate(
      question: "q", answer: "a", context: ["a"], metrics: [RubricLLM::Metrics::Faithfulness]
    )

    assert_nil result.scores[:faithfulness]
    assert_includes result.errors[:faithfulness], "invalid claims"
    refute_predicate result, :valid?
  end

  def test_raises_for_empty_judge_response
    stub_judge_response("")
    metric = RubricLLM::Metrics::Faithfulness.new(judge: RubricLLM::Judge.new(config: no_retry_config))

    error = assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a", context: ["c"]) }
    assert_includes error.message, "empty"
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

  private

  def no_retry_config
    RubricLLM::Config.new(max_retries: 0, retry_base_delay: 0.0)
  end
end
