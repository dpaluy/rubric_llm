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

      def backend
        judge.respond_to?(:config) ? judge.config.judge_backend : :chat
      end

      def evaluate_for_backend(sample)
        return call_system_one(**sample) if backend == :system_one
        return judge.evaluate_metric(self, sample) if backend == :cascade

        call_chat(**sample)
      end

      def system_one_eval(state:, questions:)
        runner = judge.is_a?(RubricLLM::Judge) ? Judges::SystemOne.new(config: judge.config) : judge
        runner.call(state:, questions:)
      end

      private

      def judge_eval(system_prompt:, user_prompt:)
        judge.call(system_prompt:, user_prompt:)
      end

      def chat_details(details)
        usage = judge.respond_to?(:last_usage) ? judge.last_usage : nil
        usage = nil if usage.respond_to?(:empty?) && usage.empty?
        details.merge(usage:)
      end

      def system_one_details(response, answer: nil)
        details = {
          backend: :system_one,
          model: response.model,
          usage: response.usage,
          latency_ms: response.latency_ms,
          raw_answers: response.answers.transform_values(&:raw),
          raw_response: response.raw
        }
        details[:confidence] = answer.confidence if answer.respond_to?(:confidence)
        details[:probability] = answer.probability if answer.respond_to?(:probability)
        details
      end

      def combined_system_one_details(responses)
        {
          backend: :system_one,
          model: responses.map(&:model).uniq.one? ? responses.first.model : responses.map(&:model),
          usage: responses.each_with_object({ "input_tokens" => 0, "output_tokens" => 0 }) do |response, usage|
            usage.each_key { |key| usage[key] += response.usage.fetch(key, 0) }
          end,
          latency_ms: responses.sum(&:latency_ms),
          raw_answers: responses.each_with_object({}) { |response, raw| raw.merge!(response.answers.transform_values(&:raw)) },
          raw_responses: responses.map(&:raw)
        }
      end

      def sentence_batches(sentences)
        sentences.each_slice(judge.config.typesafe_sentence_limit).to_a
      end

      def empty_sentences
        { score: nil, details: { backend: :system_one, error: "No sentences provided" } }
      end
    end
  end
end
