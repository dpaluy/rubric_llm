# frozen_string_literal: true

require "json"

module RubricLLM
  module SystemOne
    class Question
      TYPES = %i[choice score noul].freeze

      attr_reader :id, :type, :instructions, :criteria

      def self.choice(id, instructions:, criteria: {}) # rubocop:disable Naming/MethodParameterName
        new(id:, type: :choice, instructions:, criteria:)
      end

      def self.score(id, instructions:, levels: []) # rubocop:disable Naming/MethodParameterName
        new(id:, type: :score, instructions:, criteria: levels)
      end

      def self.noul(id, instructions:, criteria: nil) # rubocop:disable Naming/MethodParameterName
        new(id:, type: :noul, instructions:, criteria:)
      end

      def initialize(id:, type:, instructions:, criteria: nil) # rubocop:disable Naming/MethodParameterName
        raise ConfigurationError, "question id must be a String or Symbol" unless id.is_a?(String) || id.is_a?(Symbol)

        @id = immutable_copy(id.to_s)
        @type = type.respond_to?(:to_sym) ? type.to_sym : type
        @instructions = immutable_copy(instructions)
        @criteria = immutable_copy(criteria)
        validate!
      end

      def to_h
        { type: type.to_s, instructions: }.tap do |wire|
          wire[:criteria] = wire_criteria unless criteria.nil?
        end
      end

      private

      def validate!
        raise ConfigurationError, "question id must be non-empty" if id.strip.empty?
        raise ConfigurationError, "question type must be choice, score, or noul" unless TYPES.include?(type)
        unless description?(instructions) && !blank?(instructions)
          raise ConfigurationError, "question instructions must be a non-empty String, Hash, or Array"
        end

        validate_json!(instructions, "instructions")
        send("validate_#{type}!")
      end

      def immutable_copy(value)
        case value
        when String then value.dup.freeze
        when Array then value.map { |item| immutable_copy(item) }.freeze
        when Hash
          value.to_h { |key, item| [immutable_copy(key), immutable_copy(item)] }.freeze
        else value
        end
      end

      def validate_choice!
        unless criteria.is_a?(Hash) && criteria.length.between?(1, 255)
          raise ConfigurationError, "choice criteria must contain 1..255 options"
        end
        raise ConfigurationError, "choice option names must be non-empty" if criteria.keys.any? { |key| key.to_s.strip.empty? }
        raise ConfigurationError, "choice option names must be unique" unless criteria.keys.map(&:to_s).uniq.length == criteria.length

        criteria.each_value { |value| validate_description!(value, "choice criterion", allow_nil: true) }
      end

      def validate_score!
        raise ConfigurationError, "score levels must contain 2..10 entries" unless criteria.is_a?(Array) && criteria.length.between?(2, 10)

        criteria.each { |level| validate_description!(level, "score level") }
      end

      def validate_noul!
        return if criteria.nil?
        raise ConfigurationError, "noul criteria must be a Hash with true and false keys" unless criteria.is_a?(Hash)

        keys = criteria.keys.map(&:to_s).sort
        raise ConfigurationError, "noul criteria must contain only true and false keys" unless keys == %w[false true]

        return if criteria.values.all? { |value| value.is_a?(String) && !value.empty? }

        raise ConfigurationError, "noul criteria values must be non-empty strings"
      end

      def wire_criteria
        return criteria.transform_keys(&:to_s) if criteria.is_a?(Hash)

        criteria
      end

      def validate_description!(value, label, allow_nil: false)
        return if allow_nil && value.nil?
        raise ConfigurationError, "#{label} must be a non-empty String, Hash, or Array" unless description?(value) && !blank?(value)

        validate_json!(value, label)
      end

      def validate_json!(value, label)
        return if json_value?(value)

        raise ConfigurationError, "#{label} must be JSON-compatible"
      end

      def description?(value)
        value.is_a?(String) || value.is_a?(Hash) || value.is_a?(Array)
      end

      def json_value?(value)
        case value
        when String, Integer, TrueClass, FalseClass, NilClass then true
        when Float then value.finite?
        when Array then value.all? { |item| json_value?(item) }
        when Hash
          value.all? { |key, item| (key.is_a?(String) || key.is_a?(Symbol)) && json_value?(item) }
        else false
        end
      end

      def blank?(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end
    end
  end
end
