# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Correctness < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer matches the ground truth.
        Consider semantic equivalence, not just exact string matching.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(question:, answer:, ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        user_prompt = <<~PROMPT
          Question: #{question}

          Answer: #{answer}

          Ground Truth: #{ground_truth}

          Evaluate the correctness of the answer compared to the ground truth.
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
