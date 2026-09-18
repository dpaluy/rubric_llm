# frozen_string_literal: true

module RubricLLM
  class Evaluator
    DEFAULT_METRICS = [
      Metrics::Faithfulness,
      Metrics::Relevance,
      Metrics::Correctness,
      Metrics::FactualAccuracy,
      Metrics::ContextPrecision,
      Metrics::ContextRecall
    ].freeze

    attr_reader :config, :metric_classes

    def initialize(config:, metrics: nil)
      @config = config
      @metric_classes = metrics || DEFAULT_METRICS
    end

    def call(question:, answer:, context: [], ground_truth: nil)
      judge = build_judge
      scores = {}
      details = {}

      metric_classes.each do |metric_class|
        metric = metric_class.new(judge:)
        name = metric_name(metric_class)
        ensure_backend_supported!(metric)

        sample = { question:, answer:, context:, ground_truth: }
        result = config.judge_backend == :system_one ? metric.call_system_one(**sample) : metric.call(**sample)
        scores[name] = result[:score]
        details[name] = result[:details]
      rescue JudgeError => e
        scores[name] = nil
        details[name] = { error: e.message }
      end

      Result.new(scores:, details:, sample: { question:, answer:, context:, ground_truth: })
    end

    private

    def build_judge
      return Judges::SystemOne.new(config:) if config.judge_backend == :system_one

      Judges::Chat.new(config:)
    end

    def ensure_backend_supported!(metric)
      return unless config.judge_backend == :system_one && !metric.respond_to?(:call_system_one)

      raise ConfigurationError, "#{metric.class} does not support the system_one backend; implement #call_system_one"
    end

    def metric_name(klass)
      klass.name.split("::").last
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
           .to_sym
    end
  end
end
