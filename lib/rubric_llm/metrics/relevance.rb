# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Relevance < Base
      INSTRUCTION = "How well does `answer` answer `question`?"
      LEVELS = [
        "The answer ignores the question.",
        "The answer touches the topic but does not answer the question.",
        "The answer partially answers the question.",
        "The answer answers the question with minor gaps or padding.",
        "The answer directly and completely answers the question."
      ].freeze
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer is relevant to the question.
        A relevant answer directly addresses what was asked.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(**sample)
        backend == :system_one ? call_system_one(**sample) : call_chat(**sample)
      end

      def call_chat(question:, answer:, **)
        user_prompt = <<~PROMPT
          Question: #{question}

          Answer: #{answer}

          Evaluate how relevant the answer is to the question.
        PROMPT
        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        { score: Float(result["score"]), details: { reasoning: result["reasoning"] } }
      end

      def call_system_one(question:, answer:, **)
        questions = [SystemOne::Question.score("relevance", instructions: INSTRUCTION, levels: LEVELS)]
        response = system_one_eval(state: { question:, answer: }, questions:)
        scored = response.answers.fetch("relevance")
        details = system_one_details(response, answer: scored).merge(
          score: scored.score, legend: scored.legend, probabilities: scored.probabilities
        )
        { score: scored.normalized, details: }
      end
    end
  end
end
