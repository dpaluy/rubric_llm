# frozen_string_literal: true

require "ruby_llm"

require_relative "rubric_llm/version"
require_relative "rubric_llm/errors"
require_relative "rubric_llm/config"
require_relative "rubric_llm/judge"
require_relative "rubric_llm/metrics/base"
require_relative "rubric_llm/metrics/faithfulness"
require_relative "rubric_llm/metrics/relevance"
require_relative "rubric_llm/metrics/correctness"
require_relative "rubric_llm/metrics/context_precision"
require_relative "rubric_llm/metrics/context_recall"
require_relative "rubric_llm/metrics/factual_accuracy"
require_relative "rubric_llm/result"
require_relative "rubric_llm/evaluator"
require_relative "rubric_llm/report"
require_relative "rubric_llm/comparison"
require_relative "rubric_llm/retrieval_result"

module RubricLLM
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      new_config = Config.new(**config.to_h)
      yield(new_config)
      new_config.validate!
      @config = new_config
    end

    def reset_configuration!
      @config = nil
    end

    # Evaluate a single sample against all (or selected) metrics.
    #
    #   result = RubricLLM.evaluate(
    #     question: "What is the capital of France?",
    #     answer: "Paris",
    #     context: ["Paris is the capital of France."],
    #     ground_truth: "Paris"
    #   )
    def evaluate(question:, answer:, context: [], ground_truth: nil, metrics: nil,
                 config: self.config, custom_prompt: nil)
      config = apply_custom_prompt(config, custom_prompt)
      evaluator = Evaluator.new(config:, metrics:)
      evaluator.call(question:, answer:, context:, ground_truth:)
    end

    # Evaluate a batch of samples and return a Report.
    #
    #   report = RubricLLM.evaluate_batch(dataset)
    #   report = RubricLLM.evaluate_batch(dataset, concurrency: 4)
    def evaluate_batch(dataset, metrics: nil, config: self.config, custom_prompt: nil, concurrency: nil)
      config = apply_custom_prompt(config, custom_prompt)
      pool_size = concurrency || config.concurrency
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      results = if pool_size > 1
                  evaluate_batch_threaded(dataset, config:, metrics:, pool_size:)
                else
                  evaluator = Evaluator.new(config:, metrics:)
                  dataset.map { |sample| evaluate_sample(evaluator, sample) }
                end

      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      Report.new(results:, duration:)
    end

    # Compare two Reports with paired t-tests.
    #
    #   comparison = RubricLLM.compare(report_a, report_b)
    def compare(report_a, report_b)
      Comparison.new(report_a, report_b)
    end

    # Evaluate retrieval quality without LLM calls.
    #
    #   result = RubricLLM.evaluate_retrieval(retrieved: [...], relevant: [...])
    def evaluate_retrieval(retrieved:, relevant:)
      RetrievalResult.new(retrieved:, relevant:)
    end

    private

    def evaluate_sample(evaluator, sample)
      sample = normalize_sample(sample)
      evaluator.call(
        question: sample[:question],
        answer: sample[:answer],
        context: sample.fetch(:context, []),
        ground_truth: sample[:ground_truth]
      )
    end

    def evaluate_batch_threaded(dataset, config:, metrics:, pool_size:)
      queue = Queue.new
      dataset.each_with_index { |sample, i| queue << [sample, i] }
      pool_size.times { queue << nil } # poison pills

      results = Array.new(dataset.size)
      mutex = Mutex.new

      threads = pool_size.times.map do
        Thread.new do
          evaluator = Evaluator.new(config:, metrics:)
          while (item = queue.pop)
            sample, index = item
            result = evaluate_sample(evaluator, sample)
            mutex.synchronize { results[index] = result }
          end
        end
      end

      threads.each(&:join)
      results
    end

    def apply_custom_prompt(config, custom_prompt)
      return config unless custom_prompt

      Config.new(**config.to_h.compact, custom_prompt:)
    end

    def normalize_sample(sample)
      sample.transform_keys(&:to_sym)
    end
  end
end
