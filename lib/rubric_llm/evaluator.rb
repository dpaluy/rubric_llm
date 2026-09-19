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

    def self.build_judge(config:)
      return Judges::SystemOne.new(config:) if config.judge_backend == :system_one
      return Judges::Cascade.new(config:) if config.judge_backend == :cascade

      Judges::Chat.new(config:)
    end

    def initialize(config:, metrics: nil)
      @config = config
      @metric_classes = metrics || DEFAULT_METRICS
    end

    def call(question:, answer:, context: [], ground_truth: nil)
      judge = self.class.build_judge(config:)
      scores = {}
      details = {}

      metric_classes.each do |metric_class|
        usage_start = judge.usage_attempts.length
        name = metric_name(metric_class)
        metric = metric_class.new(judge:)
        ensure_backend_supported!(metric)

        sample = { question:, answer:, context:, ground_truth: }
        result = evaluate_metric(judge, metric, sample)
        scores[name] = result[:score]
        details[name] = result[:details]
      rescue JudgeError => e
        scores[name] = nil
        usage = UsageSummary.new(judge.usage_attempts.drop(usage_start)).total
        details[name] = { error: e.message, backend: config.judge_backend, usage: }
      ensure
        if details[name] && usage_start
          attempts = judge.usage_attempts.drop(usage_start)
          details[name] = details[name].merge(usage_attempts: attempts)
        end
      end

      Result.new(scores:, details:, sample: { question:, answer:, context:, ground_truth: })
    end

    private

    def evaluate_metric(judge, metric, sample)
      return metric.call_system_one(**sample) if config.judge_backend == :system_one
      return metric.call(**sample) unless config.judge_backend == :cascade && metric.respond_to?(:call_system_one)

      judge.evaluate_metric(metric, sample)
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
