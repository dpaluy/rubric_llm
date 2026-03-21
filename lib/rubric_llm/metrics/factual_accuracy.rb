# frozen_string_literal: true

module RubricLLM
  module Metrics
    class FactualAccuracy < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Compare the factual claims in the candidate answer against the reference answer.
        Identify any discrepancies where the candidate states something different from the reference.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "discrepancies": [{"claim": "<candidate claim>", "reference": "<what reference says>", "severity": "minor|major"}],
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(answer:, ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        user_prompt = <<~PROMPT
          Candidate Answer: #{answer}

          Reference Answer: #{ground_truth}

          Compare the factual claims and identify any discrepancies.
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
            discrepancies: result["discrepancies"],
            reasoning: result["reasoning"]
          }
        }
      end
    end
  end
end
