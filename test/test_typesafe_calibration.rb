# frozen_string_literal: true

require "test_helper"
require_relative "../examples/typesafe_calibration"

class TestTypeSafeCalibration < Minitest::Test
  def test_statistics_handle_missing_and_constant_values
    assert_nil TypeSafeCalibration.pearson([1.0, nil], [1.0, 2.0])
    assert_nil TypeSafeCalibration.pearson([1.0, 1.0], [0.5, 0.7])
    assert_in_delta 0.2, TypeSafeCalibration.mad([1.0, nil, 0.4], [0.8, 0.2, 0.2])
    assert_nil TypeSafeCalibration.mad([nil], [0.2])
  end

  def test_offline_synthetic_harness_prints_three_backends_and_comparisons
    reports = [report(0.8), report(0.7), report(0.9, escalated: true)]
    output, = capture_io do
      TypeSafeCalibration.run(
        [{ question: "synthetic question", answer: "synthetic answer" }],
        config: RubricLLM::Config.new(typesafe_api_key: "offline", judge_backend: :chat),
        evaluator: ->(*) { reports.shift }
      )
    end

    assert_includes output, "chat vs system_one"
    assert_includes output, "chat vs cascade"
    assert_includes output, "system_one vs cascade"
    assert_includes output, "tokens: unknown"
    assert_includes output, "Pearson=n/a (missing or constant values)"
  end

  private

  def report(score, escalated: nil)
    details = escalated.nil? ? {} : { relevance: { escalated: } }
    result = RubricLLM::Result.new(scores: { relevance: score }, details:, sample: { question: "synthetic question" })
    RubricLLM::Report.new(results: [result], duration: 0.01)
  end
end
