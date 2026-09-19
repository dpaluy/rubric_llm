# frozen_string_literal: true

module RubricLLM
  module Judges
    class Cascade
      include UsageTracking

      attr_reader :last_usage

      def initialize(config:, system_one: nil, chat: nil)
        @config = config
        @system_one = system_one || SystemOne.new(config:)
        @chat = chat || Chat.new(config:)
      end

      def config
        @fallback_config || @config
      end

      # Metrics use the same judge interface for both strategies.
      def call(state: nil, questions: nil, system_prompt: nil, user_prompt: nil)
        if questions
          call_system_one(state:, questions:)
        else
          call_chat(system_prompt:, user_prompt:)
        end
      end

      def evaluate_metric(metric, sample)
        @responses = []
        @last_usage = nil
        system_result = metric.call_system_one(**sample)
        return system_result if @responses.empty?

        reasons = @responses.filter_map { |response| escalation_reason(response) }
        return cascade_result(system_result, false, nil) if reasons.empty?

        fallback(metric, sample, system_result, reasons.uniq.join("; "))
      rescue JudgeError => e
        fallback(metric, sample, { score: nil, details: system_one_failure(e) }, "System One error: #{e.message}")
      ensure
        @responses = nil
      end

      private

      def call_system_one(state:, questions:)
        usage_start = @system_one.usage_attempts.length if @system_one.respond_to?(:usage_attempts)
        response = @system_one.call(state:, questions:)
        @responses << response if @responses
        response
      ensure
        if usage_start
          usage_attempts.concat(@system_one.usage_attempts.drop(usage_start))
        else
          record_usage(backend: :system_one, provider: :typesafe, model: response&.model || config.typesafe_model, usage: response&.usage)
        end
      end

      def call_chat(system_prompt:, user_prompt:)
        usage_start = @chat.usage_attempts.length if @chat.respond_to?(:usage_attempts)
        @last_usage = nil
        @chat.call(system_prompt:, user_prompt:)
      ensure
        @last_usage = @chat.last_usage if @chat.respond_to?(:last_usage)
        if usage_start
          usage_attempts.concat(@chat.usage_attempts.drop(usage_start))
        else
          record_usage(backend: :chat, provider: config.judge_provider, model: config.judge_model, usage: @last_usage)
        end
      end

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
        @fallback_config = Config.new(**@config.to_h, judge_backend: :chat)
        strategy = metric.respond_to?(:call_chat) ? :call_chat : :call
        chat_result = metric.public_send(strategy, **sample)
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
      ensure
        @fallback_config = nil
      end

      def cascade_result(result, escalated, reason)
        result.merge(details: result[:details].merge(escalated:, escalation_reason: reason))
      end
    end
  end
end
