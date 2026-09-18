# frozen_string_literal: true

module RubricLLM
  module Metrics
    class Correctness < Base
      SCORE_INSTRUCTION = "How closely does `answer` match `ground_truth` for `question`?"
      CONTRADICTION_INSTRUCTION = "Does `answer` contradict `ground_truth` on any specific fact?"
      LEVELS = [
        "The answer contradicts the ground truth.",
        "The answer is mostly wrong compared with the ground truth.",
        "The answer partially matches the ground truth.",
        "The answer matches the ground truth with minor omissions.",
        "The answer is semantically equivalent to the ground truth."
      ].freeze
      SYSTEM_PROMPT = <<~PROMPT
        You are an evaluation judge. Assess whether the answer matches the ground truth.
        Consider semantic equivalence, not just exact string matching.

        Respond with JSON only:
        {
          "score": <float 0.0-1.0>,
          "reasoning": "<brief explanation>"
        }
      PROMPT

      def call(**sample)
        backend == :system_one ? call_system_one(**sample) : call_chat(**sample)
      end

      def call_chat(question:, answer:, ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        user_prompt = <<~PROMPT
          Question: #{question}

          Answer: #{answer}

          Ground Truth: #{ground_truth}

          Evaluate the correctness of the answer compared to the ground truth.
        PROMPT
        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        { score: Float(result["score"]), details: { reasoning: result["reasoning"] } }
      end

      def call_system_one(question:, answer:, ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        questions = [
          SystemOne::Question.score("correctness", instructions: SCORE_INSTRUCTION, levels: LEVELS),
          SystemOne::Question.noul("contradiction", instructions: CONTRADICTION_INSTRUCTION)
        ]
        response = system_one_eval(state: { question:, answer:, ground_truth: }, questions:)
        scored = response.answers.fetch("correctness")
        contradiction = response.answers.fetch("contradiction")
        details = system_one_details(response, answer: scored).merge(
          score: scored.score, legend: scored.legend, probabilities: scored.probabilities,
          contradiction_probability: contradiction.probability
        )
        { score: scored.normalized, details: }
      end
    end
  end
end
