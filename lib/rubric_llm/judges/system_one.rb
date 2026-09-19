# frozen_string_literal: true

module RubricLLM
  module Judges
    class SystemOne
      include UsageTracking

      attr_reader :config, :client

      def initialize(config:, client: nil)
        @config = config
        @client = client || RubricLLM::SystemOne::Client.new(config:)
      end

      def call(state:, questions:)
        usage_start = client.usage_attempts.length if client.respond_to?(:usage_attempts)
        response = client.call(state:, questions: questions.map { |question| question_with_custom_prompt(question) })
      ensure
        if usage_start
          usage_attempts.concat(client.usage_attempts.drop(usage_start))
        else
          record_usage(backend: :system_one, provider: :typesafe, model: response&.model || config.typesafe_model, usage: response&.usage)
        end
      end

      private

      def question_with_custom_prompt(question)
        return question unless config.custom_prompt

        instructions = if question.instructions.is_a?(String)
                         "#{question.instructions}\n\nAdditional instructions:\n#{config.custom_prompt}"
                       else
                         [question.instructions, { "additional_instructions" => config.custom_prompt }]
                       end
        RubricLLM::SystemOne::Question.new(id: question.id, type: question.type, instructions:, criteria: question.criteria)
      end
    end
  end
end
