# frozen_string_literal: true

module RubricLLM
  module Judges
    class SystemOne
      attr_reader :config, :client

      def initialize(config:, client: nil)
        @config = config
        @client = client || RubricLLM::SystemOne::Client.new(config:)
      end

      def call(state:, questions:)
        client.call(state:, questions:)
      end
    end
  end
end
