# frozen_string_literal: true

module RubricLLM
  module SystemOne
    class RequestTracking
      attr_reader :usage_attempts

      def initialize
        @usage_attempts = []
      end

      def with_unknown_on_error(model)
        yield
      rescue StandardError
        record_unknown(model)
        raise
      end

      def record_unknown(model)
        usage_attempts << record(model, nil)
      end

      def capture_response(requested_model, response)
        usage = parsed_usage(response["usage"])
        model = response["model"]
        model = requested_model unless usage && model.is_a?(String) && !model.strip.empty?
        usage_attempts << record(model, usage)
        response
      end

      def validate_usage!(usage)
        raise JudgeError, "System One usage must be an object" unless usage.is_a?(Hash)

        %w[input_tokens output_tokens].to_h do |key|
          value = usage[key]
          raise JudgeError, "System One usage #{key} must be a non-negative integer" unless value.is_a?(Integer) && value >= 0

          [key, value]
        end
      end

      private

      def parsed_usage(usage)
        validate_usage!(usage)
      rescue JudgeError
        nil
      end

      def record(model, usage)
        { backend: :system_one, provider: :typesafe, model:, usage: }
      end
    end
  end
end
