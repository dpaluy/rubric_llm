# frozen_string_literal: true

require "test_helper"

class TestEvaluatorJudgment < Minitest::Test
  include TestSetup

  def test_evaluate_default_metrics_with_judgment_model
    answers = %i[faithfulness relevance correctness factual_accuracy context_recall].to_h { |name| [name, fake_score(2)] }
    answers[:context_recall] = fake_score(4, levels: 5)
    answers[:faithfulness] = fake_score(4, levels: 5)
    stub_judgment(answers.merge("context_1" => fake_probability(0.9)))

    result = RubricLLM.evaluate(question: "Capital?", answer: "Paris", context: ["Paris is the capital."], ground_truth: "Paris")

    assert_equal [1.0] * 6, result.scores.values
    assert_equal 6, RubyLLMStub.fake_judge.calls.size
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
