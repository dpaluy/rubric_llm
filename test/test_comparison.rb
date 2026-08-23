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

  # --- Pairing by identity ---

  def test_pairs_samples_by_question_not_position
    report_a = build_report({ "q1" => 0.5, "q2" => 0.6, "q3" => 0.7 })
    ordered_b = build_report({ "q1" => 0.8, "q2" => 0.85, "q3" => 1.0 })
    shuffled_b = build_report({ "q3" => 1.0, "q1" => 0.8, "q2" => 0.85 })

    ordered = RubricLLM::Comparison.new(report_a, ordered_b).results[:faithfulness]
    shuffled = RubricLLM::Comparison.new(report_a, shuffled_b).results[:faithfulness]

    assert_in_delta ordered[:p_value], shuffled[:p_value], 1e-12
    assert_in_delta ordered[:delta], shuffled[:delta], 1e-12
    assert_operator ordered[:p_value], :<, 0.05
  end

  def test_drops_and_warns_for_questions_missing_from_one_report
    report_a = build_report({ "q1" => 0.5, "q2" => 0.6 })
    report_b = build_report({ "q1" => 0.9, "q3" => 0.4 })
    comparison = RubricLLM::Comparison.new(report_a, report_b)

    output = capture_io { comparison.results }

    assert_match(/dropped 2 question/, output[1])
    assert_in_delta 0.5, comparison.results[:faithfulness][:mean_a], 0.001
    assert_in_delta 0.9, comparison.results[:faithfulness][:mean_b], 0.001
  end

  def test_warns_when_a_question_repeats_unevenly
    report_a = RubricLLM::Report.new(results: [
                                       result_for("q1", 0.5),
                                       result_for("q1", 0.6)
                                     ])
    report_b = RubricLLM::Report.new(results: [result_for("q1", 0.9)])

    output = capture_io { RubricLLM::Comparison.new(report_a, report_b).results }

    assert_match(/appears 2 time\(s\) in report A/, output[1])
  end

  # --- Multiple comparison correction ---

  def test_holm_adjustment_scales_by_metric_count
    report_a = build_report({ "q1" => 0.5, "q2" => 0.6, "q3" => 0.7 }, flat: 0.5)
    report_b = build_report({ "q1" => 0.8, "q2" => 0.85, "q3" => 1.0 }, flat: 0.5)

    results = RubricLLM::Comparison.new(report_a, report_b).results
    faithfulness = results[:faithfulness]

    assert_equal 2, results.size
    assert_in_delta faithfulness[:p_value] * 2, faithfulness[:p_value_adjusted], 1e-9
    assert_in_delta 1.0, results[:flat][:p_value_adjusted], 1e-9
  end

  def test_adjusted_p_value_is_never_below_the_raw_p_value
    results = @comparison.results

    results.each_value do |stats|
      assert_operator stats[:p_value_adjusted], :>=, stats[:p_value]
    end
  end

  def test_summary_reports_adjusted_p_values
    summary = @comparison.summary

    assert_includes summary, "p-adj"
    assert_includes summary, "Holm-Bonferroni"
  end

  private

  def build_report(scores_by_question, flat: nil)
    results = scores_by_question.map do |question, score|
      scores = { faithfulness: score }
      scores[:flat] = flat unless flat.nil?
      RubricLLM::Result.new(scores:, details: {}, sample: { question: })
    end

    RubricLLM::Report.new(results:)
  end

  def result_for(question, score)
    RubricLLM::Result.new(scores: { faithfulness: score }, details: {}, sample: { question: })
  end
end
