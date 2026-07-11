# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Base
      attr_reader :judge

      def initialize(judge:)
        @judge = judge
      end

      # Evaluate a single sample. Subclasses must implement this.
      #
      # Returns { score: Float (0.0-1.0), details: Hash }
      def call(question:, answer:, context: [], ground_truth: nil, **)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      private

      def judge_eval(system_prompt:, user_prompt:)
        judge.call(system_prompt:, user_prompt:)
      end
    end
  end
end
