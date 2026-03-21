# frozen_string_literal: true

module RubricLLM
  module Metrics
    class ContextRecall < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the provided contexts cover the information in the ground truth.
        Context recall measures if the retrieved documents contain enough information to construct the ground truth answer.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "covered_facts": [{"fact": "<from ground truth>", "covered": <true/false>, "source_context": <int or null>}],
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(context: [], ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?
        return { score: nil, details: { error: "No context provided" } } if Array(context).empty?

        user_prompt = <<~PROMPT
          Contexts:
          #{Array(context).each_with_index.map { |c, i| "#{i + 1}. #{c}" }.join("\n")}

          Ground Truth: #{ground_truth}

          Evaluate how well the contexts cover the facts in the ground truth.
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
            covered_facts: result["covered_facts"],
            reasoning: result["reasoning"]
          }
        }
      end
    end
  end
end
