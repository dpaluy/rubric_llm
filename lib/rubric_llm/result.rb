# frozen_string_literal: true

module RubricLLM
  class Result
    attr_reader :scores, :details, :sample

    def initialize(scores:, details:, sample: {})
      @scores = scores
      @details = details
      @sample = sample
    end

    def overall
      valid = scores.values.compact
      return nil if valid.empty?

      valid.sum / valid.size.to_f
    end

    def pass?(threshold: 0.8)
      return false unless valid?

      score = overall
      return false if score.nil?

      score >= threshold
    end

    def errors
      details.each_with_object({}) do |(name, detail), acc|
        acc[name] = detail[:error] if detail.is_a?(Hash) && detail.key?(:error)
      end
    end

    def valid?
      errors.empty?
    end

    def to_h
      { scores:, details:, overall: overall, errors: }
    end

    private

    def respond_to_missing?(name, include_private = false)
      scores.key?(name) || super
    end

    def method_missing(name, *args)
      return scores[name] if args.empty? && scores.key?(name)

      super
    end
  end
end
