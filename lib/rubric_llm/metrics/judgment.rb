# frozen_string_literal: true

module RubricLLM
  module Metrics
    # Base class for custom metrics answered by a judgment model, such as
    # TypeSafe's Jev. Declare one question; its answer becomes the score.
    #
    #   class ToneMetric < RubricLLM::Metrics::Judgment
    #     score "How professional is the tone?", ["Rude", "Neutral", "Professional"]
    #   end
    #
    #   class PolitenessMetric < RubricLLM::Metrics::Judgment
    #     probability "Is the answer polite?", yes: "Courteous wording", no: "Dismissive or rude wording"
    #   end
    #
    # A score is normalized from its level indexes onto 0.0-1.0; a probability
    # is the probability of yes. Override #judgment_input to change what the
    # judgment model sees.
    class Judgment < Base
      QUESTION_NAME = :metric

      class << self
        # Scores the sample against ordered levels, worst first.
        def score(instructions, levels)
          @question = { type: :score, instructions:, levels: }
        end

        # Scores the sample with the probability that the answer to a yes/no question is yes.
        def probability(instructions, yes: nil, no: nil) # rubocop:disable Naming/MethodParameterName
          criteria = { yes:, no: }.compact
          @question = { type: :probability, instructions:, criteria: (criteria unless criteria.empty?) }.compact
        end

        def question
          return @question if @question

          superclass.question if superclass.respond_to?(:question)
        end
      end

      def initialize(judge:)
        raise ArgumentError, "#{self.class} must declare a score or probability question" unless self.class.question

        super
      end

      def call(question:, answer:, context: [], ground_truth: nil, **)
        raise JudgeError, "#{self.class} requires a judgment model" unless judgment?

        input = judgment_input(question:, answer:, context:, ground_truth:)
        score_question(input, QUESTION_NAME, self.class.question)
      end

      private

      def judgment_input(question:, answer:, context:, ground_truth:)
        context_chunks = Base.normalize_context(context)
        { question:, answer:, context: (context_chunks unless context_chunks.empty?), ground_truth: }.compact
      end
    end
  end
end
