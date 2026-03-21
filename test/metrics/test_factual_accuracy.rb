# frozen_string_literal: true

require "test_helper"

class TestFactualAccuracy < Minitest::Test
  include TestSetup

  def test_returns_score_and_details
    response = '{"score": 0.85, "discrepancies": [{"claim": "Ruby is compiled", ' \
               '"reference": "Ruby is interpreted", "severity": "major"}], "reasoning": "one discrepancy found"}'
    stub_judge_response(response)
    metric = RubricLLM::Metrics::FactualAccuracy.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(answer: "Ruby is compiled", ground_truth: "Ruby is interpreted")

    assert_in_delta 0.85, result[:score]
    assert_equal 1, result[:details][:discrepancies].size
    assert_equal "major", result[:details][:discrepancies].first["severity"]
    assert_equal "one discrepancy found", result[:details][:reasoning]
  end

  def test_perfect_score_with_no_discrepancies
    stub_judge_response('{"score": 1.0, "discrepancies": [], "reasoning": "no discrepancies"}')
    metric = RubricLLM::Metrics::FactualAccuracy.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(answer: "Paris is the capital", ground_truth: "Paris is the capital of France")

    assert_in_delta 1.0, result[:score]
    assert_empty result[:details][:discrepancies]
  end

  def test_nil_without_ground_truth
    metric = RubricLLM::Metrics::FactualAccuracy.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(answer: "some answer")

    assert_nil result[:score]
    assert_equal "No ground truth provided", result[:details][:error]
  end

  def test_handles_nil_judge_response
    stub_judge_response("")
    metric = RubricLLM::Metrics::FactualAccuracy.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(answer: "a", ground_truth: "b")

    assert_nil result[:score]
  end
end
