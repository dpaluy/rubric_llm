# frozen_string_literal: true

module RubricLLM
  module Metrics
    class ContextPrecision < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the retrieved contexts are relevant to the question.
        Context precision is the fraction of retrieved chunks useful for answering the question.
        Classify every numbered chunk once, in order. Use the displayed 1-based index.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "context_scores": [{"index": <int>, "relevant": <true/false>, "reason": "<brief>"}],
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(question:, context: [], **)
        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        user_prompt = <<~PROMPT
          Question: #{question}

          Contexts:
          #{context_chunks.each_with_index.map { |c, i| "#{i + 1}. #{c}" }.join("\n")}

          Evaluate how relevant each context is to the question.
        PROMPT

        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        normalize(result, context_chunks.size)
      end

      private

      def normalize(result, count)
        context_scores = checked_items(result, "context_scores", label: "context scores", count:, value_key: "relevant", text_key: "reason")
        unless context_scores.each_with_index.all? { |item, index| item["index"].is_a?(Integer) && item["index"] == index + 1 }
          raise JudgeError, "Judge response has invalid context indices"
        end

        {
          score: fraction(context_scores, "relevant"),
          details: { context_scores:, reasoning: reasoning_for(result) }
        }
      end
    end
  end
end
