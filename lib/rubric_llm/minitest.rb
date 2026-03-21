# frozen_string_literal: true

require "rubric_llm"

module RubricLLM
  module Assertions
    def assert_faithful(answer, context, question: "", threshold: 0.8, config: RubricLLM.config)
      result = evaluate_metric(Metrics::Faithfulness, question:, answer:, context:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Expected faithfulness >= #{threshold}, got #{score || "nil"}.#{failure_details(result)}"
    end

    def assert_relevant(question, answer, threshold: 0.8, config: RubricLLM.config)
      result = evaluate_metric(Metrics::Relevance, question:, answer:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Expected relevance >= #{threshold}, got #{score || "nil"}.#{failure_details(result)}"
    end

    def assert_correct(answer, ground_truth, question: "", threshold: 0.8, config: RubricLLM.config)
      result = evaluate_metric(Metrics::Correctness, question:, answer:, ground_truth:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Expected correctness >= #{threshold}, got #{score || "nil"}.#{failure_details(result)}"
    end

    def refute_hallucination(answer, context, question: "", threshold: 0.8, config: RubricLLM.config)
      result = evaluate_metric(Metrics::Faithfulness, question:, answer:, context:, config:)
      score = result[:score]

      assert score && score >= threshold,
             "Detected hallucination: faithfulness #{score || "nil"} < #{threshold}.#{failure_details(result)}"
    end

    private

    def evaluate_metric(metric_class, config:, **)
      judge = Judge.new(config:)
      metric = metric_class.new(judge:)
      metric.call(**)
    end

    def failure_details(result)
      details = result[:details]
      return "" unless details.is_a?(Hash)

      if details[:claims]
        unsupported = details[:claims]&.select { |c| c.is_a?(Hash) && c["supported"] == false }
        return " Claims not supported: #{unsupported.map { |c| c["claim"] }}" if unsupported&.any?
      end

      details[:reasoning] ? " #{details[:reasoning]}" : ""
    end
  end
end
