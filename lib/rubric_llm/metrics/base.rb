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

      def judgment?
        judge.judgment?
      end

      # Ask a judgment model typed questions and return the named answers.
      def judgment_eval(input, questions)
        judgment = judge.judge(input, questions:)
        questions.keys.to_h do |name|
          answer = judgment[name]
          raise JudgeError, "Judgment is missing answer #{name}" if answer.nil?

          [name, answer]
        end
      end

      # Score the input with a single judgment question built from the metric's
      # JUDGMENT_INSTRUCTIONS and ordered JUDGMENT_LEVELS.
      def score_judgment(input, name:)
        score_question(input, name, { type: :score, instructions: self.class::JUDGMENT_INSTRUCTIONS,
                                      levels: self.class::JUDGMENT_LEVELS })
      end

      # Ask one score or probability question and turn its answer into a metric result.
      # A score is normalized from its level indexes; a probability is the probability of yes.
      def score_question(input, name, question)
        answer = judgment_eval(input, { name => question }).fetch(name)
        case question[:type]
        when :score
          { score: normalized_score(answer),
            details: { backend: :judgment, probabilities: answer.probabilities, confidence: answer.confidence } }
        when :probability
          probability = probability_of(answer)
          { score: probability, details: { backend: :judgment, probability: } }
        else raise ArgumentError, "Unsupported judgment question type: #{question[:type].inspect}"
        end
      rescue NoMethodError
        raise JudgeError, "Judgment answer #{name} is malformed"
      end

      # Map a judgment score from its level indexes onto 0.0-1.0.
      def normalized_score(answer)
        levels = answer.levels.size
        raise JudgeError, "Judgment score needs at least two levels" if levels < 2

        unit_interval(Float(answer.score) / (levels - 1), "score")
      rescue ArgumentError, TypeError, NoMethodError
        raise JudgeError, "Judgment score must be numeric with ordered levels"
      end

      def probability_of(answer)
        unit_interval(Float(answer.probability), "probability")
      rescue ArgumentError, TypeError, NoMethodError
        raise JudgeError, "Judgment probability must be numeric"
      end

      def unit_interval(value, label)
        raise JudgeError, "Judgment #{label} must be between 0.0 and 1.0" unless value.finite? && value.between?(0.0, 1.0)

        value
      end

      def checked_items(result, key, label:, value_key:, text_key:, count: nil)
        items = result[key]
        valid = items.is_a?(Array) && items.any? && (count.nil? || items.size == count)
        valid &&= items.all? do |item|
          item.is_a?(Hash) && item[text_key].is_a?(String) && !item[text_key].strip.empty? &&
            [true, false].include?(item[value_key])
        end
        raise JudgeError, "Judge response has invalid #{label}" unless valid

        items
      end

      def fraction(items, key)
        items.count { |item| item[key] }.to_f / items.size
      end

      def reasoning_for(result)
        reasoning = result["reasoning"]
        raise JudgeError, "Judge response missing reasoning" unless reasoning.is_a?(String) && !reasoning.strip.empty?

        reasoning
      end
    end
  end
end
