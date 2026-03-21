# frozen_string_literal: true

module RubricLLM
  class Comparison
    attr_reader :report_a, :report_b

    def initialize(report_a, report_b)
      @report_a = report_a
      @report_b = report_b

      return if report_a.results.size == report_b.results.size

      warn "[RubricLLM] Comparison reports have different sizes " \
           "(#{report_a.results.size} vs #{report_b.results.size}). " \
           "Unmatched pairs will be dropped."
    end

    def results
      @results ||= compute_results
    end

    def summary
      lines = ["A/B Comparison"]
      lines << ("=" * 70)
      lines << "Metric                      A        B    Delta    p-value  Sig"
      lines << ("-" * 70)

      results.each do |metric, r|
        lines << format("%-20s %8.3f %8.3f %+8.3f %10.4f %4s",
                        metric, r[:mean_a], r[:mean_b], r[:delta], r[:p_value], r[:significance])
      end

      lines.join("\n")
    end

    def significant_improvements(alpha: 0.05)
      results.select { |_, r| r[:p_value] < alpha && r[:delta].positive? }.keys
    end

    def significant_regressions(alpha: 0.05)
      results.select { |_, r| r[:p_value] < alpha && r[:delta].negative? }.keys
    end

    private

    def compute_results
      metrics = (report_a.metric_stats.keys | report_b.metric_stats.keys)

      metrics.each_with_object({}) do |metric, hash|
        paired_scores = report_a.scores_for(metric)
                                .zip(report_b.scores_for(metric))
                                .select { |score_a, score_b| !score_a.nil? && !score_b.nil? }

        next if paired_scores.empty?

        scores_a, scores_b = paired_scores.transpose

        mean_a = scores_a.sum / scores_a.size.to_f
        mean_b = scores_b.sum / scores_b.size.to_f
        delta = mean_b - mean_a
        p_value = paired_t_test(scores_a, scores_b)

        hash[metric] = {
          mean_a:,
          mean_b:,
          delta:,
          p_value:,
          significance: significance_marker(p_value)
        }
      end
    end

    def paired_t_test(a, b)
      n = [a.size, b.size].min
      return 1.0 if n < 2

      diffs = a.first(n).zip(b.first(n)).map { |x, y| y - x }
      mean_d = diffs.sum / n.to_f
      var_d = diffs.sum { |d| (d - mean_d)**2 } / (n - 1).to_f
      se = Math.sqrt(var_d / n)

      return 1.0 if se.zero?

      t = mean_d / se
      df = n - 1

      # Two-tailed p-value approximation using Student's t-distribution
      two_tailed_p(t.abs, df)
    end

    # Two-tailed p-value for Student's t-distribution.
    # p = I_x(df/2, 1/2) where x = df/(df + t²)
    def two_tailed_p(t, df)
      x = df / (df + (t**2))
      regularized_beta(x, df / 2.0, 0.5)
    rescue StandardError
      1.0
    end

    # Regularized incomplete beta function via continued fraction (Lentz's method).
    def regularized_beta(x, a, b)
      return 0.0 if x <= 0.0
      return 1.0 if x >= 1.0

      ln_beta = Math.lgamma(a)[0] + Math.lgamma(b)[0] - Math.lgamma(a + b)[0]
      front = Math.exp((a * Math.log(x)) + (b * Math.log(1.0 - x)) - ln_beta) / a

      # Lentz's continued fraction
      c = 1.0
      d = 1.0 - ((a + b) * x / (a + 1.0))
      d = 1.0 if d.abs < 1e-30
      d = 1.0 / d
      f = d

      (1..200).each do |m|
        # Even step
        numerator = m * (b - m) * x / ((a + (2 * m) - 1) * (a + (2 * m)))
        d = 1.0 + (numerator * d)
        d = 1e-30 if d.abs < 1e-30
        c = 1.0 + (numerator / c)
        c = 1e-30 if c.abs < 1e-30
        d = 1.0 / d
        f *= c * d

        # Odd step
        numerator = -(a + m) * (a + b + m) * x / ((a + (2 * m)) * (a + (2 * m) + 1))
        d = 1.0 + (numerator * d)
        d = 1e-30 if d.abs < 1e-30
        c = 1.0 + (numerator / c)
        c = 1e-30 if c.abs < 1e-30
        d = 1.0 / d
        delta = c * d
        f *= delta

        break if (delta - 1.0).abs < 1e-10
      end

      front * f
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
