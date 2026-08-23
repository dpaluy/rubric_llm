# frozen_string_literal: true

module RubricLLM
  class Comparison
    attr_reader :report_a, :report_b

    def initialize(report_a, report_b)
      @report_a = report_a
      @report_b = report_b
    end

    def results
      @results ||= compute_results
    end

    def summary
      lines = ["A/B Comparison"]
      lines << ("=" * 80)
      lines << "Metric                      A        B    Delta    p-value      p-adj  Sig"
      lines << ("-" * 80)

      results.each do |metric, r|
        lines << format("%-20s %8.3f %8.3f %+8.3f %10.4f %10.4f %4s",
                        metric, r[:mean_a], r[:mean_b], r[:delta], r[:p_value], r[:p_value_adjusted],
                        r[:significance])
      end

      lines << ""
      lines << "p-adj: Holm-Bonferroni adjusted across #{results.size} metrics. Significance uses p-adj."
      lines.join("\n")
    end

    def significant_improvements(alpha: 0.05)
      results.select { |_, r| r[:p_value_adjusted] < alpha && r[:delta].positive? }.keys
    end

    def significant_regressions(alpha: 0.05)
      results.select { |_, r| r[:p_value_adjusted] < alpha && r[:delta].negative? }.keys
    end

    private

    def compute_results
      metrics = (report_a.metric_stats.keys | report_b.metric_stats.keys)

      raw = metrics.each_with_object({}) do |metric, hash|
        stats = metric_stats(metric)
        hash[metric] = stats if stats
      end

      apply_holm_correction(raw)
    end

    def metric_stats(metric)
      paired_scores = paired_results
                      .map { |result_a, result_b| [result_a.scores[metric], result_b.scores[metric]] }
                      .reject { |score_a, score_b| score_a.nil? || score_b.nil? }

      return nil if paired_scores.empty?

      scores_a, scores_b = paired_scores.transpose
      mean_a = scores_a.sum / scores_a.size.to_f
      mean_b = scores_b.sum / scores_b.size.to_f

      {
        mean_a:,
        mean_b:,
        delta: mean_b - mean_a,
        p_value: Statistics.paired_t_test(scores_a, scores_b)
      }
    end

    # A paired t-test requires the same sample on both sides. Pair by question
    # instead of array position so a reordered dataset stays valid.
    def paired_results
      @paired_results ||= build_pairs
    end

    def build_pairs
      groups_a = report_a.results.group_by { |result| pair_key(result) }
      groups_b = report_b.results.group_by { |result| pair_key(result) }

      warn_unkeyed(groups_a[nil].to_a.size + groups_b[nil].to_a.size)

      matched = groups_a.keys & groups_b.keys
      warn_unmatched(((groups_a.keys | groups_b.keys) - matched).compact)

      matched.flat_map do |key|
        list_a = groups_a[key]
        list_b = groups_b[key]
        warn_uneven(key, list_a.size, list_b.size) unless list_a.size == list_b.size

        size = [list_a.size, list_b.size].min
        list_a.first(size).zip(list_b.first(size))
      end
    end

    def pair_key(result)
      sample = result.sample
      sample.is_a?(Hash) ? sample[:question] : nil
    end

    # Results with no sample[:question] share one bucket and pair by position,
    # which is the behaviour identity pairing exists to replace. Say so.
    def warn_unkeyed(count)
      return if count.zero?

      warn "[RubricLLM] #{count} result(s) have no sample[:question]. They share one bucket and " \
           "pair by position. Give every sample a :question to pair them reliably."
    end

    def warn_unmatched(keys)
      return if keys.empty?

      warn "[RubricLLM] Comparison dropped #{keys.size} question(s) present in only one report. " \
           "Paired tests need the same questions on both sides."
    end

    def warn_uneven(key, size_a, size_b)
      warn "[RubricLLM] Question #{key.inspect} appears #{size_a} time(s) in report A and " \
           "#{size_b} time(s) in report B. Extra occurrences are dropped."
    end

    # One t-test per metric inflates the family-wise error rate, so adjust
    # before calling any metric significant.
    def apply_holm_correction(results)
      metrics = results.keys
      adjusted = Statistics.holm_adjust(metrics.map { |metric| results[metric][:p_value] })

      metrics.each_with_index do |metric, index|
        results[metric] = results[metric].merge(
          p_value_adjusted: adjusted[index],
          significance: significance_marker(adjusted[index])
        )
      end

      results
    end

    def significance_marker(p)
      if p < 0.001 then "***"
      elsif p < 0.01 then "**"
      elsif p < 0.05 then "*"
      else ""
      end
    end
  end
end
