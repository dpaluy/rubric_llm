# frozen_string_literal: true

require "test_helper"

class TestComparison < Minitest::Test
  def setup
    results_a = [
      RubricLLM::Result.new(scores: { faithfulness: 0.7, relevance: 0.6 }, details: {}, sample: {}),
      RubricLLM::Result.new(scores: { faithfulness: 0.6, relevance: 0.5 }, details: {}, sample: {}),
      RubricLLM::Result.new(scores: { faithfulness: 0.65, relevance: 0.55 }, details: {}, sample: {})
    ]
    results_b = [
      RubricLLM::Result.new(scores: { faithfulness: 0.9, relevance: 0.6 }, details: {}, sample: {}),
      RubricLLM::Result.new(scores: { faithfulness: 0.85, relevance: 0.5 }, details: {}, sample: {}),
      RubricLLM::Result.new(scores: { faithfulness: 0.88, relevance: 0.55 }, details: {}, sample: {})
    ]

    @report_a = RubricLLM::Report.new(results: results_a)
    @report_b = RubricLLM::Report.new(results: results_b)
    @comparison = RubricLLM::Comparison.new(@report_a, @report_b)
  end

  def test_results_have_metrics
    results = @comparison.results

    assert results.key?(:faithfulness)
    assert results.key?(:relevance)
  end

  def test_delta_positive_when_b_better
    results = @comparison.results

    assert_operator results[:faithfulness][:delta], :>, 0
  end

  def test_delta_zero_when_equal
    results = @comparison.results

    assert_in_delta 0.0, results[:relevance][:delta], 0.001
  end

  def test_summary_format
    summary = @comparison.summary

    assert_includes summary, "A/B Comparison"
    assert_includes summary, "faithfulness"
    assert_includes summary, "Delta"
  end

  def test_significant_improvements
    improvements = @comparison.significant_improvements(alpha: 0.05)

    assert_includes improvements, :faithfulness
  end

  def test_significant_regressions_empty_when_none
    regressions = @comparison.significant_regressions(alpha: 0.05)

    refute_includes regressions, :relevance
  end

  def test_warns_on_mismatched_report_sizes
    report_a = RubricLLM::Report.new(results: [
                                       RubricLLM::Result.new(scores: { faithfulness: 0.5 }, details: {}, sample: {})
                                     ])
    report_b = RubricLLM::Report.new(results: [
                                       RubricLLM::Result.new(scores: { faithfulness: 0.6 }, details: {}, sample: {}),
                                       RubricLLM::Result.new(scores: { faithfulness: 0.7 }, details: {}, sample: {})
                                     ])

    output = capture_io { RubricLLM::Comparison.new(report_a, report_b) }

    assert_match(/different sizes/, output[1])
  end

  def test_results_keep_pairs_aligned_when_filtering_nil_scores
    report_a = RubricLLM::Report.new(results: [
                                       RubricLLM::Result.new(scores: { faithfulness: 0.2 }, details: {}, sample: {}),
                                       RubricLLM::Result.new(scores: { faithfulness: nil }, details: {}, sample: {}),
                                       RubricLLM::Result.new(scores: { faithfulness: 0.9 }, details: {}, sample: {})
                                     ])
    report_b = RubricLLM::Report.new(results: [
                                       RubricLLM::Result.new(scores: { faithfulness: 0.4 }, details: {}, sample: {}),
                                       RubricLLM::Result.new(scores: { faithfulness: 0.6 }, details: {}, sample: {}),
                                       RubricLLM::Result.new(scores: { faithfulness: 1.0 }, details: {}, sample: {})
                                     ])

    result = RubricLLM::Comparison.new(report_a, report_b).results[:faithfulness]

    assert_in_delta 0.55, result[:mean_a], 0.001
    assert_in_delta 0.7, result[:mean_b], 0.001
    assert_in_delta 0.15, result[:delta], 0.001
  end
end
