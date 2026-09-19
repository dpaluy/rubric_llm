# frozen_string_literal: true

require "rubric_llm"
require_relative "failure_details"

module RubricLLM
  module Assertions
    def assert_faithful(answer, context, question: "", threshold: DEFAULT_THRESHOLD, config: RubricLLM.config)
      require_context!(context)
      result = evaluate_metric(Metrics::Faithfulness, question:, answer:, context:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Expected faithfulness >= #{threshold}, got #{score || "nil"}.#{failure_details(result)}"
    end

    def assert_relevant(question, answer, threshold: DEFAULT_THRESHOLD, config: RubricLLM.config)
      result = evaluate_metric(Metrics::Relevance, question:, answer:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Expected relevance >= #{threshold}, got #{score || "nil"}.#{failure_details(result)}"
    end

    def assert_correct(answer, ground_truth, question: "", threshold: DEFAULT_THRESHOLD, config: RubricLLM.config)
      result = evaluate_metric(Metrics::Correctness, question:, answer:, ground_truth:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Expected correctness >= #{threshold}, got #{score || "nil"}.#{failure_details(result)}"
    end

    def refute_hallucination(answer, context, question: "", threshold: DEFAULT_THRESHOLD, config: RubricLLM.config)
      require_context!(context)
      result = evaluate_metric(Metrics::Faithfulness, question:, answer:, context:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Detected hallucination: faithfulness #{score || "nil"} < #{threshold}.#{failure_details(result)}"
    end

    private

    def require_context!(context)
      Metrics::Base.require_context!(context)
    end

    def evaluate_metric(metric_class, config:, **)
      judge = Evaluator.build_judge(config:)
      metric = metric_class.new(judge:)
      metric.call(**)
    end

    def failure_details(result)
      FailureDetails.format(result[:details])
    end
  end
end
