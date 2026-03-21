# frozen_string_literal: true

require "test_helper"

class TestCorrectness < Minitest::Test
  include TestSetup

  def test_returns_score
    stub_judge_response('{"score": 0.95, "reasoning": "matches"}')
    metric = RubricLLM::Metrics::Correctness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "Capital?", answer: "Paris", ground_truth: "Paris")

    assert_in_delta 0.95, result[:score]
  end

  def test_nil_without_ground_truth
    metric = RubricLLM::Metrics::Correctness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "q", answer: "a")

    assert_nil result[:score]
    assert_equal "No ground truth provided", result[:details][:error]
  end
end
