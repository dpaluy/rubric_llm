# frozen_string_literal: true

require "test_helper"

class TestContextPrecision < Minitest::Test
  include TestSetup

  def test_returns_score
    stub_judge_response('{"score": 0.8, "context_scores": [{"index": 0, "relevant": true, "reason": "ok"}], "reasoning": "good"}')
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "What is Ruby?", context: ["Ruby is a language"])

    assert_in_delta 0.8, result[:score]
  end

  def test_nil_without_context
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "q")

    assert_nil result[:score]
    assert_equal "No context provided", result[:details][:error]
  end
end
