# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Faithfulness < Base
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

      def call(question:, answer:, context: [], **)
        context_chunks = Array(context).map { |chunk| chunk.to_s.strip }.reject(&:empty?)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        user_prompt = <<~PROMPT
          Context: #{context_chunks.join("\n\n")}

          Question: #{question}

          Answer: #{answer}

          Evaluate the faithfulness of the answer to the context.
        PROMPT

        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        normalize(result)
      end

      private

      def normalize(result)
        return { score: nil, details: result } unless result.is_a?(Hash) && result["score"]

        {
          score: Float(result["score"]).clamp(0.0, 1.0),
          details: {
            claims: result["claims"],
            reasoning: result["reasoning"]
          }
        }
      end
    end
  end
end
