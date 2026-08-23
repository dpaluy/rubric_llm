# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Base
      # Single source of truth for what counts as usable context.
      # Blank and whitespace-only chunks are dropped.
      def self.normalize_context(context)
        Array(context).map { |chunk| chunk.to_s.strip }.reject(&:empty?)
      end

      # An empty context cannot produce a faithfulness score. Reject it as a caller
      # error instead of letting a nil score read as a quality verdict.
      def self.require_context!(context)
        return unless normalize_context(context).empty?

        raise ArgumentError, "context must contain at least one non-empty entry"
      end

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
