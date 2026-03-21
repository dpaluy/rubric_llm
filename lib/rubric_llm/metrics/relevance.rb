# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Relevance < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer is relevant to the question.
        A relevant answer directly addresses what was asked.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(question:, answer:, **)
        user_prompt = <<~PROMPT
          Question: #{question}

          Answer: #{answer}

          Evaluate how relevant the answer is to the question.
        PROMPT

        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        normalize(result)
      end

      private

      def normalize(result)
        return { score: nil, details: result } unless result.is_a?(Hash) && result["score"]

        {
          score: Float(result["score"]).clamp(0.0, 1.0),
          details: { reasoning: result["reasoning"] }
        }
      end
    end
  end
end
