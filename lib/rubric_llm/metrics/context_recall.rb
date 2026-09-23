# frozen_string_literal: true

module RubricLLM
  module Metrics
    class ContextRecall < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the provided contexts cover the information in the ground truth.
        Context recall is the fraction of facts in the ground truth supported by the contexts.
        List every distinct factual claim in the ground truth. Mark it covered only if a numbered
        context supports it, and use that context's 1-based index as source_context.
        Use null for source_context when a fact is not covered.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "covered_facts": [{"fact": "<from ground truth>", "covered": <true/false>, "source_context": <int or null>}],
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(context: [], ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        user_prompt = <<~PROMPT
          Contexts:
          #{context_chunks.each_with_index.map { |c, i| "#{i + 1}. #{c}" }.join("\n")}

          Ground Truth: #{ground_truth}

          Evaluate how well the contexts cover the facts in the ground truth.
        PROMPT

        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        normalize(result, context_chunks.size)
      end

      private

      def normalize(result, count)
        covered_facts = checked_items(result, "covered_facts", label: "covered facts", value_key: "covered", text_key: "fact")
        valid_sources = covered_facts.all? do |item|
          source = item["source_context"]
          item["covered"] ? source.is_a?(Integer) && (1..count).cover?(source) : source.nil?
        end
        raise JudgeError, "Judge response has invalid source contexts" unless valid_sources

        {
          score: fraction(covered_facts, "covered"),
          details: { covered_facts:, reasoning: reasoning_for(result) }
        }
      end
    end
  end
end
