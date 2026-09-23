# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Relevance < Base
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer is relevant to the question.
        A relevant answer directly addresses what was asked, regardless of its factual accuracy.
        Score 1.0 if it directly addresses all parts of the question, 0.5 if it addresses only
        part or is mostly tangential, and 0.0 if it does not address the question. Use intermediate
        values for partial cases and explain the score. Do not score correctness here.

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
        {
          score: Float(result["score"]),
          details: { reasoning: reasoning_for(result) }
        }
      end
    end
  end
end
