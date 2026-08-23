# frozen_string_literal: true

module RubricLLM
  # Pure statistical helpers. No LLM calls, no state.
  module Statistics
    module_function

    # Two-tailed paired t-test. Both arrays must already be paired and equal length.
    # Returns 1.0 when there is nothing to test.
    def paired_t_test(scores_a, scores_b)
      n = scores_a.size
      return 1.0 if n < 2

      diffs = scores_a.zip(scores_b).map { |x, y| y - x }
      mean_d = diffs.sum / n.to_f
      var_d = diffs.sum { |d| (d - mean_d)**2 } / (n - 1).to_f
      se = Math.sqrt(var_d / n)

      # A constant shift has no spread to test. Compare against the scale of the
      # data rather than exact zero, or float error turns it into a huge t value.
      return 1.0 if se <= Float::EPSILON * [mean_d.abs, 1.0].max

      two_tailed_p((mean_d / se).abs, n - 1)
    end

    # Two-tailed p-value for Student's t-distribution.
    # p = I_x(df/2, 1/2) where x = df/(df + t²)
    def two_tailed_p(t, df)
      x = df / (df + (t**2))
      regularized_beta(x, df / 2.0, 0.5)
    rescue Math::DomainError, ZeroDivisionError, FloatDomainError
      1.0
    end

    # Holm-Bonferroni step-down adjustment.
    # Takes p-values in any order, returns adjusted values in the same order.
    def holm_adjust(p_values)
      count = p_values.size
      return p_values.dup if count.zero?

      adjusted = Array.new(count)
      running_max = 0.0

      p_values.each_with_index.sort_by(&:first).each_with_index do |(p_value, position), rank|
        running_max = ((count - rank) * p_value).clamp(running_max, 1.0)
        adjusted[position] = running_max
      end

      adjusted
    end

    # Regularized incomplete beta function via continued fraction (Lentz's method).
    def regularized_beta(x, a, b)
      return 0.0 if x <= 0.0
      return 1.0 if x >= 1.0

      ln_beta = Math.lgamma(a + b)[0] - Math.lgamma(a)[0] - Math.lgamma(b)[0]
      front = Math.exp(ln_beta + (a * Math.log(x)) + (b * Math.log(1.0 - x)))

      result = if x < ((a + 1.0) / (a + b + 2.0))
                 front * beta_continued_fraction(a, b, x) / a
               else
                 1.0 - ((front * beta_continued_fraction(b, a, 1.0 - x)) / b)
               end

      result.clamp(0.0, 1.0)
    end

    def beta_continued_fraction(a, b, x)
      tiny = 1e-30
      qab = a + b
      qap = a + 1.0
      qam = a - 1.0

      c = 1.0
      d = 1.0 - ((qab * x) / qap)
      d = tiny if d.abs < tiny
      d = 1.0 / d
      fraction = d

      (1..200).each do |m|
        m2 = 2 * m

        numerator = (m * (b - m) * x) / ((qam + m2) * (a + m2))
        d = 1.0 + (numerator * d)
        d = tiny if d.abs < tiny
        c = 1.0 + (numerator / c)
        c = tiny if c.abs < tiny
        d = 1.0 / d
        fraction *= c * d

        numerator = -((a + m) * (qab + m) * x) / ((a + m2) * (qap + m2))
        d = 1.0 + (numerator * d)
        d = tiny if d.abs < tiny
        c = 1.0 + (numerator / c)
        c = tiny if c.abs < tiny
        d = 1.0 / d
        delta = c * d
        fraction *= delta

        break if (delta - 1.0).abs < 1e-12
      end

      fraction
    end
  end
end
