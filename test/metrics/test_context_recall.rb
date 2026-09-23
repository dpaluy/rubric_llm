# frozen_string_literal: true

require "test_helper"

class TestContextRecall < Minitest::Test
  include TestSetup

  def test_returns_score
    stub_judge_response('{"score": 0.75, "covered_facts": [{"fact": "Paris", "covered": true, "source_context": 1}], "reasoning": "ok"}')
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(context: ["Paris is the capital"], ground_truth: "Paris")

    assert_in_delta 1.0, result[:score]
  end

  def test_score_counts_covered_facts
    stub_judge_response('{"score": 1.0, "covered_facts": ' \
                        '[{"fact": "a", "covered": true, "source_context": 1}, ' \
                        '{"fact": "b", "covered": false, "source_context": null}], "reasoning": "one missing"}')
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    result = metric.call(context: ["a"], ground_truth: "a and b")

    assert_in_delta 0.5, result[:score]
  end

  def test_rejects_invalid_source_context
    stub_judge_response('{"score": 1.0, "covered_facts": [{"fact": "a", "covered": true, "source_context": 2}], "reasoning": "ok"}')
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    assert_raises(RubricLLM::JudgeError) { metric.call(context: ["a"], ground_truth: "a") }
  end

  def test_rejects_decimal_source_contexts
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    [1.0, 1.5].each do |source|
      stub_judge_response(JSON.generate(score: 1.0, reasoning: "covered",
                                        covered_facts: [{ fact: "a", covered: true, source_context: source }]))

      error = assert_raises(RubricLLM::JudgeError) { metric.call(context: %w[a b], ground_truth: "a") }
      assert_includes error.message, "invalid source contexts"
    end
  end

  def test_rejects_source_for_uncovered_fact
    stub_judge_response(JSON.generate(score: 0.0, reasoning: "not covered",
                                      covered_facts: [{ fact: "b", covered: false, source_context: 1 }]))
    metric = RubricLLM::Metrics::ContextRecall.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    error = assert_raises(RubricLLM::JudgeError) { metric.call(context: ["a"], ground_truth: "b") }
    assert_includes error.message, "invalid source contexts"
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
