# frozen_string_literal: true

require "json"

module RubricLLM
  class Report
    attr_reader :results, :duration

    def initialize(results:, duration: nil)
      @results = results
      @duration = duration
    end

    def metric_stats
      @metric_stats ||= compute_stats
    end

    def worst(n)
      results.sort_by { |r| r.overall || Float::INFINITY }.first(n)
    end

    def failures(threshold: 0.8)
      results.reject { |r| r.pass?(threshold:) }
    end

    def summary
      lines = ["RubricLLM Evaluation Report"]
      lines << ("=" * 40)
      lines << "Samples: #{results.size}"
      lines << "Duration: #{"%.1f" % duration}s" if duration

      metric_stats.each do |metric, stats|
        lines << format("  %-20s  mean=%.3f  std=%.3f  min=%.3f  max=%.3f  n=%d",
                        metric, stats[:mean], stats[:std], stats[:min], stats[:max], stats[:count])
      end

      lines.join("\n")
    end

    def export_csv(path)
      require "csv" # optional dependency — add `gem "csv"` to your Gemfile if missing
      metrics = all_metric_names
      CSV.open(path, "w") do |csv|
        csv << ["question", "answer", "overall", *metrics]
        results.each do |result|
          csv << [
            result.sample[:question],
            result.sample[:answer],
            result.overall,
            *metrics.map { |m| result.scores[m] }
          ]
        end
      end
    end

    def export_json(path)
      File.write(path, JSON.pretty_generate(serializable_hash))
    end

    def to_json(*)
      JSON.generate(serializable_hash, *)
    end

    # Scores for a single metric across all results (for Comparison).
    def scores_for(metric)
      results.map { |r| r.scores[metric] }
    end

    private

    def serializable_hash
      {
        summary: metric_stats,
        duration:,
        results: results.map(&:to_h)
      }
    end

    def all_metric_names
      results.flat_map { |r| r.scores.keys }.uniq
    end

    def compute_stats
      all_metric_names.each_with_object({}) do |metric, stats|
        values = results.filter_map { |r| r.scores[metric] }
        next if values.empty?

        mean = values.sum / values.size.to_f
        variance = values.sum { |v| (v - mean)**2 } / [values.size - 1, 1].max.to_f
        std = Math.sqrt(variance)

        stats[metric] = {
          mean:,
          std:,
          min: values.min,
          max: values.max,
          count: values.size
        }
      end
    end
  end
end
