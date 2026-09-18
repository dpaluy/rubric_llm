# frozen_string_literal: true

module RubricLLM
  module Metrics
    class FactualAccuracy < Base
      INSTRUCTION = "Does `sentences[%<index>d]` state something that conflicts with `ground_truth`?"
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

      def call(**sample)
        backend == :system_one ? call_system_one(**sample) : call_chat(**sample)
      end

      def call_chat(answer:, ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        user_prompt = <<~PROMPT
          Candidate Answer: #{answer}

          Reference Answer: #{ground_truth}

          Compare the factual claims and identify any discrepancies.
        PROMPT
        result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt:)
        {
          score: Float(result["score"]),
          details: { discrepancies: result["discrepancies"], reasoning: result["reasoning"] }
        }
      end

      def call_system_one(answer:, ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        sentences = Text.sentences(answer)
        return empty_sentences if sentences.empty?

        responses = sentence_responses(answer, sentences, ground_truth)
        probabilities = responses.flat_map { |response| response.answers.values.map(&:probability) }
        conflict_mean = probabilities.sum / probabilities.length.to_f
        details = combined_system_one_details(responses).merge(probabilities:, conflict_mean:)
        { score: 1.0 - conflict_mean, details: }
      end

      private

      def sentence_responses(answer, sentences, ground_truth)
        offset = 0
        sentence_batches(sentences).map do |batch|
          questions = batch.each_index.map do |index|
            SystemOne::Question.noul("sentence_#{offset + index}", instructions: format(INSTRUCTION, index:))
          end
          offset += batch.length
          system_one_eval(state: { answer:, ground_truth:, sentences: batch }, questions:)
        end
      end
    end
  end
end
