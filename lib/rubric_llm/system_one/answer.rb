# frozen_string_literal: true

require "json"

module RubricLLM
  module SystemOne
    module Answer
      class Base
        attr_reader :raw

        def initialize(raw)
          @raw = raw.freeze
        end

        private

        def number!(value, field, range: 0.0..1.0)
          number = Float(value)
          raise JudgeError, "System One #{field} must be finite and in #{range}" unless number.finite? && range.cover?(number)

          number
        rescue ArgumentError, TypeError
          raise JudgeError, "System One #{field} must be numeric"
        end

        def distribution!(value, expected_keys)
          raise JudgeError, "System One probabilities must be an object" unless value.is_a?(Hash)
          raise JudgeError, "System One probability keys do not match the question" unless value.keys.sort == expected_keys.sort

          parsed = value.to_h { |key, probability| [key, number!(probability, "probability")] }
          raise JudgeError, "System One probabilities must sum to 1" unless (parsed.values.sum - 1.0).abs <= 0.001

          parsed.freeze
        end
      end

      class Noul < Base
        attr_reader :probability

        def initialize(raw)
          super
          @probability = number!(raw["noul"], "noul")
        end

        alias noul probability

        def normalized(invert: false)
          invert ? 1.0 - probability : probability
        end
      end

      class Choice < Base
        attr_reader :choice, :probabilities, :confidence

        def initialize(raw, question)
          super(raw)
          keys = question.criteria.keys.map(&:to_s)
          @choice = raw["choice"]
          raise JudgeError, "System One choice is not an offered option" unless keys.include?(choice)

          @probabilities = distribution!(raw["probabilities"], keys)
          @confidence = number!(raw["confidence"], "confidence")
        end

        def normalized(mapping:)
          value = mapping.fetch(choice) { mapping.fetch(choice.to_sym) }
          number!(value, "choice mapping")
        rescue KeyError
          raise ConfigurationError, "choice mapping is missing #{choice.inspect}"
        end
      end

      class Score < Base
        attr_reader :score, :legend, :probabilities, :confidence, :level_count

        def initialize(raw, question)
          super(raw)
          @level_count = question.criteria.length
          keys = Array.new(level_count, &:to_s)
          @score = number!(raw["score"], "score", range: 0.0..(level_count - 1).to_f)
          @legend = raw["legend"]
          levels = JSON.parse(JSON.generate(question.criteria))
          expected_legend = levels.each_with_index.to_h { |level, index| [index.to_s, level] }
          raise JudgeError, "System One score legend does not match the question" unless legend == expected_legend

          @probabilities = distribution!(raw["probabilities"], keys)
          @confidence = number!(raw["confidence"], "confidence")
        end

        def normalized
          score / (level_count - 1)
        end
      end
    end

    class Response
      attr_reader :answers, :usage, :model, :latency_ms, :raw

      def initialize(answers:, usage:, model:, latency_ms:, raw:)
        @answers = answers.freeze
        @usage = usage.freeze
        @model = model.freeze
        @latency_ms = latency_ms
        @raw = raw.freeze
      end
    end
  end
end
