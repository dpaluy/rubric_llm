# frozen_string_literal: true

module RubricLLM
  module Judges
    class Cascade
      attr_reader :config, :last_usage

      def initialize(config:, system_one: nil, chat: nil)
        @config = config
        @system_one = system_one || SystemOne.new(config:)
        @chat = chat || Chat.new(config:)
      end

      # Metrics use the same judge interface for both strategies.
      def call(state: nil, questions: nil, system_prompt: nil, user_prompt: nil)
        if questions
          response = @system_one.call(state:, questions:)
          @responses << response if @responses
          response
        else
          @last_usage = nil
          begin
            @chat.call(system_prompt:, user_prompt:)
          ensure
            @last_usage = @chat.last_usage
          end
        end
      end

      def evaluate_metric(metric, sample)
        @responses = []
        system_result = metric.call_system_one(**sample)
        reasons = @responses.filter_map { |response| escalation_reason(response) }
        return cascade_result(system_result, false, nil) if reasons.empty?

        fallback(metric, sample, system_result, reasons.uniq.join("; "))
      rescue JudgeError => e
        fallback(metric, sample, { score: nil, details: system_one_failure(e) }, "System One error: #{e.message}")
      ensure
        @responses = nil
      end

      private

      def escalation_reason(response)
        if config.cascade_policy
          return "custom policy" if config.cascade_policy.call(response)

          return nil
        end

        response.answers.each_value do |answer|
          if answer.respond_to?(:confidence) && !answer.confidence.nil? && answer.confidence < config.cascade_confidence
            return "confidence #{answer.confidence} below #{config.cascade_confidence}"
          end
          if answer.respond_to?(:probability) && !answer.probability.nil? && config.cascade_noul_band.cover?(answer.probability)
            return "noul probability #{answer.probability} inside #{config.cascade_noul_band}"
          end
        end
        nil
      end

      def system_one_failure(error)
        responses = @responses || []
        completed_usage = responses.each_with_object({ "input_tokens" => 0, "output_tokens" => 0 }) do |response, total|
          total.each_key { |key| total[key] += response.usage.fetch(key, 0) }
        end
        completed_usage = nil if responses.empty?
        {
          error: error.message, backend: :system_one, usage: nil, completed_usage:, raw_responses: responses.map(&:raw)
        }
      end

      def fallback(metric, sample, system_result, reason)
        chat_result = metric.call_chat(**sample)
        details = chat_result[:details].merge(
          system_one: system_result[:details], escalated: true, escalation_reason: reason
        )
        { score: chat_result[:score], details: }
      rescue JudgeError => e
        {
          score: nil,
          details: {
            error: e.message, usage: @last_usage, system_one: system_result[:details], escalated: true,
            escalation_reason: reason, fallback_error: e.message
          }
        }
      end

      def cascade_result(result, escalated, reason)
        result.merge(details: result[:details].merge(escalated:, escalation_reason: reason))
      end
    end
  end
end
