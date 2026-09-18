# frozen_string_literal: true

module RubricLLM
  module Metrics
    class ContextRecall < Base
      INSTRUCTION = "Is the information in `sentences[%<index>d]` present in `context`?"
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

      def call(**sample)
        evaluate_for_backend(sample)
      end

      def call_chat(context: [], ground_truth: nil, **)
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
        {
          score: Float(result["score"]),
          details: chat_details(covered_facts: result["covered_facts"], reasoning: result["reasoning"])
        }
      end

      def call_system_one(context: [], ground_truth: nil, **)
        return { score: nil, details: { error: "No ground truth provided" } } if ground_truth.nil?

        context_chunks = Base.normalize_context(context)
        return { score: nil, details: { error: "No context provided" } } if context_chunks.empty?

        sentences = Text.sentences(ground_truth)
        return empty_sentences if sentences.empty?

        responses = sentence_responses(sentences, context_chunks)
        probabilities = responses.flat_map { |response| response.answers.values.map(&:probability) }
        details = combined_system_one_details(responses).merge(probabilities:)
        { score: probabilities.sum / probabilities.length.to_f, details: }
      end

      private

      def sentence_responses(sentences, context)
        offset = 0
        sentence_batches(sentences).map do |batch|
          questions = batch.each_index.map do |index|
            SystemOne::Question.noul("sentence_#{offset + index}", instructions: format(INSTRUCTION, index:))
          end
          offset += batch.length
          system_one_eval(state: { context:, sentences: batch }, questions:)
        end
      end
    end
  end
end
