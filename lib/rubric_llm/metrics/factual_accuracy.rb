# frozen_string_literal: true

module RubricLLM
  module Metrics
    class FactualAccuracy < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Compare the factual claims in the candidate answer against the reference answer.
        Identify contradictions in candidate factual claims against the reference. Do not penalize
        missing reference facts, which correctness measures. Score 1.0 if there are no contradictions,
        0.5 if minor factual contradictions affect part of the answer, and 0.0 if major contradictions
        undermine the answer. Use intermediate values for partial cases. Explain the score and list
        each contradiction with severity minor or major. If the reference does not establish whether
        a claim is true, do not call it a contradiction.

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
        discrepancies = result["discrepancies"]
        unless discrepancies.is_a?(Array) && discrepancies.all? { |item| valid_discrepancy?(item) }
          raise JudgeError, "Judge response has invalid discrepancies"
        end

        score = Float(result["score"])
        raise JudgeError, "Judge response score conflicts with no discrepancies" if discrepancies.empty? && score < 1.0
        raise JudgeError, "Judge response score conflicts with discrepancies" if discrepancies.any? && score >= 1.0

        {
          score:,
          details: { discrepancies:, reasoning: reasoning_for(result) }
        }
      end

      def valid_discrepancy?(item)
        item.is_a?(Hash) && %w[claim reference].all? { |key| item[key].is_a?(String) && !item[key].strip.empty? } &&
          %w[minor major].include?(item["severity"])
      end
    end
  end
end
