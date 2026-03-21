# frozen_string_literal: true

require "test_helper"

class TestContextRecall < Minitest::Test
  include TestSetup

  def test_returns_score
    stub_judge_response('{"score": 0.75, "covered_facts": [{"fact": "Paris", "covered": true, "source_context": 0}], "reasoning": "ok"}')
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(context: ["Paris is the capital"], ground_truth: "Paris")

    assert_in_delta 0.75, result[:score]
  end

  def test_nil_without_ground_truth
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(context: ["something"])

    assert_nil result[:score]
  end

  def test_nil_without_context
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(ground_truth: "something")

    assert_nil result[:score]
  end
end
