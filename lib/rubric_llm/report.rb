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

    def escalation_stats
      @escalation_stats ||= all_metric_names.each_with_object({}) do |metric, stats|
        attempted = results.count { |result| !result.details.dig(metric, :escalated).nil? }
        next if attempted.zero?

        escalated = results.count { |result| result.details.dig(metric, :escalated) == true }
        stats[metric] = { escalated:, total: attempted, rate: escalated / attempted.to_f }
      end
    end

    def total_usage
      usage_summary.total
    end

    def usage_complete?
      usage_summary.complete?
    end

    def usage_by_model
      usage_summary.by_model
    end

    def worst(n)
      results.sort_by { |r| r.overall || -Float::INFINITY }.first(n)
    end

    def failures(threshold: DEFAULT_THRESHOLD)
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
        append_escalation_line(lines, metric, "")
      end
      (escalation_stats.keys - metric_stats.keys).each { |metric| append_escalation_line(lines, metric, metric) }

      error_count = error_counts.values.sum
      affected_samples = results.count { |r| r.errors.any? }
      lines << "Errors: #{error_count} metric errors across #{affected_samples} samples" if error_count.positive?

      lines.join("\n")
    end

    def export_csv(path)
      require "csv"
      metrics = all_metric_names
      escalation_metrics = metrics.select { |metric| escalation_stats.key?(metric) }
      CSV.open(path, "w") do |csv|
        csv << ["question", "answer", "overall", *metrics, *escalation_metrics.map { |metric| "#{metric}_escalated" }]
        results.each do |result|
          csv << [
            result.sample[:question],
            result.sample[:answer],
            result.overall,
            *metrics.map { |m| result.scores[m] },
            *escalation_metrics.map { |m| result.details.dig(m, :escalated) }
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
      data = { summary: metric_stats, duration:, errors: error_counts, results: results.map(&:to_h) }
      data[:escalations] = escalation_stats unless escalation_stats.empty?
      data[:usage_complete] = usage_complete? if usage_summary.records.any?
      data[:usage] = total_usage if total_usage
      data[:usage_by_model] = usage_by_model if usage_summary.records.any?
      data
    end

    def all_metric_names
      results.flat_map { |r| r.scores.keys }.uniq
    end

    def error_counts
      counts = Hash.new(0)
      results.each { |r| r.errors.each_key { |name| counts[name] += 1 } }
      counts
    end

    def usage_summary
      UsageSummary.from_results(results)
    end

    def append_escalation_line(lines, metric, label)
      escalation = escalation_stats[metric]
      return unless escalation

      lines << format("  %-20s  escalated: %d/%d (%.1f%%)", label, escalation[:escalated], escalation[:total],
                      escalation[:rate] * 100)
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
