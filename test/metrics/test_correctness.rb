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

  def test_rejects_missing_reasoning
    stub_judge_response('{"score": 0.95}')
    metric = RubricLLM::Metrics::Correctness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a", ground_truth: "a") }
  end

  def test_nil_without_ground_truth
    metric = RubricLLM::Metrics::Correctness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "q", answer: "a")

    assert_nil result[:score]
    assert_equal "No ground truth provided", result[:details][:error]
  end

  def test_judgment_model_scores_correctness_levels
    stub_judgment({ correctness: fake_score(2) })
    metric = RubricLLM::Metrics::Correctness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "Capital?", answer: "Paris", ground_truth: "Paris")

    assert_in_delta 1.0, result[:score]
    assert_equal({ question: "Capital?", answer: "Paris", ground_truth: "Paris" }, RubyLLMStub.fake_judge.last_call[:input])
  end

  def test_judgment_model_keeps_ground_truth_guard
    stub_judgment
    metric = RubricLLM::Metrics::Correctness.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "q", answer: "a")

    assert_nil result[:score]
    assert_empty RubyLLMStub.fake_judge.calls
  end
end
