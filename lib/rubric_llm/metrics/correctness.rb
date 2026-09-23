# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Correctness < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer matches the ground truth.
        Consider semantic equivalence, not just exact string matching. Score the answer against
        the question and reference: 1.0 if it fully answers with no material errors, 0.5 if it
        is partly correct but misses required information or includes a material error, and 0.0
        if it is wrong or does not answer. Use intermediate values for partial cases and explain
        what is correct, missing, or wrong. Do not require irrelevant reference details.

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
        {
          score: Float(result["score"]),
          details: { reasoning: reasoning_for(result) }
        }
      end
    end
  end
end
