# frozen_string_literal: true

require "test_helper"

class TestStatistics < Minitest::Test
  Stats = RubricLLM::Statistics

  # --- Paired t-test ---

  def test_paired_t_test_returns_one_for_fewer_than_two_pairs
    assert_in_delta 1.0, Stats.paired_t_test([0.5], [0.9])
    assert_in_delta 1.0, Stats.paired_t_test([], [])
  end

  def test_paired_t_test_returns_one_when_every_difference_is_identical
    assert_in_delta 1.0, Stats.paired_t_test([0.1, 0.2, 0.3], [0.4, 0.5, 0.6])
  end

  def test_paired_t_test_matches_known_t_table_value
    # diffs = [0.3, 0.25, 0.3], t = 17.0, df = 2
    p_value = Stats.paired_t_test([0.5, 0.6, 0.7], [0.8, 0.85, 1.0])

    assert_in_delta 0.003442, p_value, 1e-5
  end

  def test_paired_t_test_is_symmetric_in_magnitude
    forward = Stats.paired_t_test([0.5, 0.6, 0.7], [0.8, 0.85, 1.0])
    reverse = Stats.paired_t_test([0.8, 0.85, 1.0], [0.5, 0.6, 0.7])

    assert_in_delta forward, reverse, 1e-12
  end

  # --- Two-tailed p ---

  def test_two_tailed_p_handles_values_close_to_one
    p_value = Stats.two_tailed_p(0.02105086415353341, 72)

    assert_in_delta 0.9832633107858819, p_value, 1e-9
  end

  def test_two_tailed_p_matches_t_table_at_the_five_percent_boundary
    # Critical t for df = 2 at alpha = 0.05 is 4.302653
    assert_in_delta 0.05, Stats.two_tailed_p(4.302653, 2), 1e-6
  end

  def test_two_tailed_p_does_not_swallow_unexpected_errors
    buggy = Stats.dup
    original_verbose = $VERBOSE
    $VERBOSE = nil
    buggy.define_singleton_method(:regularized_beta) { |*| raise "continued fraction bug" }
    $VERBOSE = original_verbose

    assert_raises(RuntimeError) { buggy.two_tailed_p(1.0, 5) }
  end

  # --- Holm-Bonferroni ---

  def test_holm_adjust_scales_the_smallest_p_value_by_the_count
    adjusted = Stats.holm_adjust([0.01, 1.0])

    assert_in_delta 0.02, adjusted[0], 1e-12
    assert_in_delta 1.0, adjusted[1], 1e-12
  end

  def test_holm_adjust_preserves_input_order
    adjusted = Stats.holm_adjust([1.0, 0.01])

    assert_in_delta 1.0, adjusted[0], 1e-12
    assert_in_delta 0.02, adjusted[1], 1e-12
  end

  def test_holm_adjust_is_monotonic_and_never_below_the_raw_value
    raw = [0.04, 0.005, 0.02, 0.9]
    adjusted = Stats.holm_adjust(raw)

    raw.each_with_index { |p_value, i| assert_operator adjusted[i], :>=, p_value }

    by_raw_rank = raw.each_index.sort_by { |i| raw[i] }
    in_rank_order = by_raw_rank.map { |i| adjusted[i] }

    assert_equal adjusted.sort, in_rank_order
  end

  def test_holm_adjust_caps_at_one
    Stats.holm_adjust([0.6, 0.7, 0.8]).each do |p_value|
      assert_operator p_value, :<=, 1.0
    end
  end

  def test_holm_adjust_handles_an_empty_list
    assert_empty Stats.holm_adjust([])
  end
end
