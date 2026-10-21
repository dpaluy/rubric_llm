# frozen_string_literal: true

require "test_helper"

class TestEvaluatorJudgment < Minitest::Test
  include TestSetup

  def test_evaluate_default_metrics_with_judgment_model
    stub_judgment({ relevance: fake_score(2), correctness: fake_score(2), "context_1" => fake_probability(0.9) })

    result = RubricLLM.evaluate(question: "Capital?", answer: "Paris", context: ["Paris is the capital."], ground_truth: "Paris")

    assert_equal({ relevance: 1.0, correctness: 1.0, context_precision: 1.0 }, result.scores.compact)
    %i[faithfulness factual_accuracy context_recall].each do |name|
      assert_nil result.scores[name]
      assert_includes result.details[name][:error], "requires a chat model"
    end
    assert_equal 3, RubyLLMStub.fake_judge.calls.size
  end

  def test_evaluate_reports_chat_only_metrics_as_errors_with_judgment_model
    stub_judgment
    chat_metric = Class.new(RubricLLM::Metrics::Base) do
      def self.name = "ChatOnlyMetric"

      def call(**)
        judge_eval(system_prompt: "s", user_prompt: "u")
      end
    end

    result = RubricLLM.evaluate(question: "q", answer: "a", metrics: [chat_metric])

    assert_nil result.scores[:chat_only_metric]
    assert_includes result.details[:chat_only_metric][:error], "requires a chat model"
  end
end
