# frozen_string_literal: true

module RubricLLM
  module Metrics
    class ContextPrecision < Base
      INSTRUCTION = "Is `context[%<index>d]` useful for answering `question`?"
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

      def call(**sample)
        backend == :system_one ? call_system_one(**sample) : call_chat(**sample)
      end

      def call_chat(question:, context: [], **)
        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        user_prompt = <<~PROMPT
          Question: #{question}

          Contexts:
          #{context_chunks.each_with_index.map { |c, i| "#{i + 1}. #{c}" }.join("\n")}

          Evaluate how relevant each context is to the question.
        PROMPT
        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        {
          score: Float(result["score"]),
          details: { context_scores: result["context_scores"], reasoning: result["reasoning"] }
        }
      end

      def call_system_one(question:, context: [], **)
        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        questions = context_chunks.each_index.map do |index|
          SystemOne::Question.noul("context_#{index}", instructions: format(INSTRUCTION, index:))
        end
        response = system_one_eval(state: { question:, context: context_chunks }, questions:)
        probabilities = response.answers.values.map(&:probability)
        details = system_one_details(response).merge(probabilities:)
        { score: probabilities.sum / probabilities.length.to_f, details: }
      end
    end
  end
end
