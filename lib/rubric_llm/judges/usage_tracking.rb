# frozen_string_literal: true

module RubricLLM
  module Judges
    module UsageTracking
      def usage_attempts
        @usage_attempts ||= []
      end

      private

      def record_usage(backend:, provider:, model:, usage:)
        usage_attempts << { backend:, provider:, model:, usage: }
      end
    end
  end
end
