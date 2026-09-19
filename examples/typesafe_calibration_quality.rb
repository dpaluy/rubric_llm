# frozen_string_literal: true

module TypeSafeCalibrationQuality # rubocop:disable Metrics/ModuleLength
  module_function

  def validate_annotations!(dataset)
    raise ArgumentError, "dataset must be an Array" unless dataset.is_a?(Array)

    dataset.each_with_index do |sample, index|
      raise ArgumentError, "sample at index #{index} must be a Hash" unless sample.is_a?(Hash)

      labels = sample[:expected_judgments] || sample["expected_judgments"]
      next if labels.nil?
      raise ArgumentError, "expected_judgments at index #{index} must be a Hash" unless labels.is_a?(Hash)

      labels.each do |metric, expected|
        raise ArgumentError, "expected_judgments metric at index #{index} must be a non-empty name" if metric.to_s.empty?
        next if [true, false].include?(expected)

        raise ArgumentError, "expected_judgments.#{metric} at index #{index} must be true or false"
      end
    end
  end

  def validate_thresholds!(thresholds)
    raise ArgumentError, "thresholds must be a Hash" unless thresholds.is_a?(Hash)

    thresholds.to_h do |metric, threshold|
      raise ArgumentError, "threshold metric names must be non-empty" if metric.to_s.empty?
      unless threshold.is_a?(Numeric) && threshold.finite? && threshold.between?(0.0, 1.0)
        raise ArgumentError, "threshold for #{metric} must be between 0.0 and 1.0"
      end

      [metric.to_sym, threshold.to_f]
    end
  end

  def print_report(backend, report)
    puts "\n#{backend}:", report.summary, "tokens: #{report.total_usage || "unknown (provider did not report usage)"}"
    print_usage_groups(report)
    puts format("wall time: %.3fs", report.duration)
    escalations = report.escalation_stats.values
    escalated = escalations.sum { |value| value[:escalated] }
    total = escalations.sum { |value| value[:total] }
    puts "escalation rate: #{total.zero? ? "n/a" : format("%.1f%%", 100.0 * escalated / total)}"
  end

  def print_usage_groups(report)
    puts "usage by model:"
    return puts("  none reported") if report.usage_by_model.empty?

    report.usage_by_model.each do |group|
      identity = [group[:backend], group[:provider], group[:model]].map { |value| value || "unknown" }.join("/")
      usage = group[:usage] || "unknown (incomplete provider usage)"
      puts "  #{identity}: calls=#{group[:calls]} tokens=#{usage} complete=#{group[:usage_complete]}"
    end
  end

  def print_quality(dataset, reports, thresholds)
    reports.each do |backend, report|
      puts "\nQuality: #{backend}"
      quality_metrics(dataset, report).each do |metric|
        print_metric_quality(dataset, report, backend, metric, thresholds.fetch(metric, RubricLLM::DEFAULT_THRESHOLD))
      end
    end
  end

  def quality_metrics(dataset, report)
    score_metrics = report.results.flat_map { |result| result.scores.keys }
    label_metrics = dataset.flat_map { |sample| expected_judgments(sample).keys }
    (score_metrics | label_metrics).map(&:to_sym).uniq.sort
  end

  def print_metric_quality(dataset, report, backend, metric, threshold)
    labeled = labeled_results(dataset, report, metric)
    return print_unknown_quality(report, metric, threshold) if labeled.empty?

    scored = scored_results(labeled, metric)
    correct = scored.count { |expected, score, _result| (score >= threshold) == expected }
    automatic_passes = scored.select do |_expected, score, result|
      score >= threshold && automatic_result?(backend, result, metric)
    end
    puts format("  %-20s threshold=%.3f labeled=%d expected_passes=%d scored=%d predicted_passes=%d " \
                "missing_scores=%d/%d labeled samples accuracy=%s false_passes=%s",
                metric, threshold, labeled.length, labeled.count { |expected, _result| expected }, scored.length,
                scored.count { |_expected, score, _result| score >= threshold },
                labeled.length - scored.length, labeled.length,
                ratio(correct, scored.length, "scored labels"),
                ratio(automatic_passes.count { |expected, _score, _result| !expected }, automatic_passes.length,
                      "labeled automatic passes"))
  end

  def labeled_results(dataset, report, metric)
    dataset.each_index.filter_map do |index|
      labels = expected_judgments(dataset[index])
      [labels.fetch(metric), report.results[index]] if labels.key?(metric)
    end
  end

  def scored_results(labeled, metric)
    labeled.filter_map do |expected, result|
      score = result&.scores&.fetch(metric, nil)
      [expected, score, result] unless score.nil?
    end
  end

  def print_unknown_quality(report, metric, threshold)
    scored_count = report.results.count { |result| !result.scores.fetch(metric, nil).nil? }
    puts format("  %-20s threshold=%.3f scored=%d missing_scores=%d/%d samples quality=unknown (no expected_judgments labels)",
                metric, threshold, scored_count, report.results.length - scored_count, report.results.length)
  end

  def expected_judgments(sample)
    labels = sample[:expected_judgments] || sample["expected_judgments"] || {}
    labels.to_h { |metric, expected| [metric.to_sym, expected] }
  end

  def automatic_result?(backend, result, metric)
    return true if backend == :system_one
    return false unless backend == :cascade

    result.details.dig(metric, :escalated) == false
  end

  def ratio(numerator, denominator, label)
    return "n/a (0 #{label})" if denominator.zero?

    format("%d/%d (%.1f%% of %s)", numerator, denominator, 100.0 * numerator / denominator, label)
  end
end
