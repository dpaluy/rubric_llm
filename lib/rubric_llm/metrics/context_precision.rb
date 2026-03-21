# frozen_string_literal: true

module RubricLLM
  module Metrics
    class ContextPrecision < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the retrieved contexts are relevant to the question.
        Context precision measures if the retrieved documents are useful for answering the question.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "context_scores": [{"index": <int>, "relevant": <true/false>, "reason": "<brief>"}],
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(question:, context: [], **)
        return { score: nil, details: { error: "No context provided" } } if Array(context).empty?

        user_prompt = <<~PROMPT
          Question: #{question}

          Contexts:
          #{Array(context).each_with_index.map { |c, i| "#{i + 1}. #{c}" }.join("\n")}

          Evaluate how relevant each context is to the question.
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
            context_scores: result["context_scores"],
            reasoning: result["reasoning"]
          }
        }
      end
    end
  end
end
