# frozen_string_literal: true

require "rubric_llm"

module RubricLLM
  module RSpecMatchers
    def be_faithful_to(context)
      FaithfulnessMatcher.new(context)
    end

    def be_correct_for(ground_truth)
      CorrectnessMatcher.new(ground_truth)
    end

    def be_relevant_to(question)
      RelevanceMatcher.new(question)
    end

    def hallucinate_from(context)
      HallucinationMatcher.new(context)
    end

    class BaseMatcher
      attr_reader :threshold, :config, :result

      def initialize
        @threshold = 0.8
        @config = RubricLLM.config
      end

      def with_threshold(value)
        @threshold = value
        self
      end

      def with_config(value)
        @config = value
        self
      end

      private

      def evaluate(metric_class, **)
        judge = Judge.new(config:)
        metric = metric_class.new(judge:)
        @result = metric.call(**)
        @result[:score]
      end
    end

    class FaithfulnessMatcher < BaseMatcher
      def initialize(context, question: nil)
        super()
        @context = context
        @question = question
      end

      def matches?(answer)
        score = evaluate(Metrics::Faithfulness, question: @question || "", answer:, context: @context)
        score && score >= threshold
      end

      def failure_message
        "expected faithfulness >= #{threshold}, got #{result[:score] || "nil"}"
      end

      def failure_message_when_negated
        "expected faithfulness < #{threshold}, got #{result[:score]}"
      end
    end

    class CorrectnessMatcher < BaseMatcher
      def initialize(ground_truth, question: nil)
        super()
        @ground_truth = ground_truth
        @question = question
      end

      def matches?(answer)
        score = evaluate(Metrics::Correctness, question: @question || "", answer:, ground_truth: @ground_truth)
        score && score >= threshold
      end

      def failure_message
        "expected correctness >= #{threshold}, got #{result[:score] || "nil"}"
      end

      def failure_message_when_negated
        "expected correctness < #{threshold}, got #{result[:score]}"
      end
    end

    class RelevanceMatcher < BaseMatcher
      def initialize(question)
        super()
        @question = question
      end

      def matches?(answer)
        score = evaluate(Metrics::Relevance, question: @question, answer:)
        score && score >= threshold
      end

      def failure_message
        "expected relevance >= #{threshold}, got #{result[:score] || "nil"}"
      end

      def failure_message_when_negated
        "expected relevance < #{threshold}, got #{result[:score]}"
      end
    end

    class HallucinationMatcher < BaseMatcher
      def initialize(context, question: nil)
        super()
        @context = context
        @question = question
      end

      def matches?(answer)
        score = evaluate(Metrics::Faithfulness, question: @question || "", answer:, context: @context)
        score.nil? || score < threshold
      end

      def failure_message
        "expected hallucination (faithfulness < #{threshold}), got #{result[:score]}"
      end

      def failure_message_when_negated
        "expected no hallucination (faithfulness >= #{threshold}), got #{result[:score] || "nil"}"
      end
    end
  end
end
