# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Faithfulness < Base
      INSTRUCTION = "Is `sentences[%<index>d]` fully supported by the information in `context`? " \
                    "Yes only if every factual element appears in or follows directly from the context."
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer is faithful to the provided context.
        A faithful answer only contains information that is supported by the context.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "claims": [{"claim": "<statement>", "supported": <true/false>}],
          "reasoning": "<brief explanation>"
        }
      PROMPT

      attr_reader :aggregate

      def initialize(judge:, aggregate: :mean)
        super(judge:)
        raise ConfigurationError, "aggregate must be mean or min" unless %i[mean min].include?(aggregate)

        @aggregate = aggregate
      end

      def call(**sample)
        backend == :system_one ? call_system_one(**sample) : call_chat(**sample)
      end

      def call_chat(question:, answer:, context: [], **)
        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        user_prompt = <<~PROMPT
          Context: #{context_chunks.join("\n\n")}

          Question: #{question}

          Answer: #{answer}

          Evaluate the faithfulness of the answer to the context.
        PROMPT

        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        { score: Float(result["score"]), details: { claims: result["claims"], reasoning: result["reasoning"] } }
      end

      def call_system_one(answer:, context: [], **)
        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        sentences = Text.sentences(answer)
        return empty_sentences if sentences.empty?

        responses = sentence_responses(sentences, context_chunks)
        probabilities = responses.flat_map { |response| response.answers.values.map(&:probability) }
        score = aggregate == :min ? probabilities.min : probabilities.sum / probabilities.length.to_f
        details = combined_system_one_details(responses).merge(
          probabilities:, mean: probabilities.sum / probabilities.length.to_f, min: probabilities.min, aggregate:
        )
        { score:, details: }
      end

      private

      def sentence_responses(sentences, context)
        offset = 0
        sentence_batches(sentences).map do |batch|
          questions = batch.each_index.map do |index|
            SystemOne::Question.noul("sentence_#{offset + index}", instructions: format(INSTRUCTION, index:))
          end
          offset += batch.length
          system_one_eval(state: { context:, sentences: batch }, questions:)
        end
      end
    end
  end
end
