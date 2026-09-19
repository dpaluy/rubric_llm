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
    assert_includes output, "quality=unknown (no expected_judgments labels)"
  end

  def test_labeled_quality_reports_missing_scores_and_only_automatic_false_passes
    dataset = [
      sample(true),
      sample(false),
      sample(false)
    ]
    reports = [
      quality_report([0.9, 0.2, nil], backend: :chat, model: "gpt-4o"),
      quality_report([0.9, 0.8, nil], backend: :system_one, model: "jev-1.13.0"),
      quality_report([0.9, 0.9, 0.9], backend: :cascade, model: "jev-1.13.0", escalations: [false, true, false])
    ]

    output, = capture_io do
      TypeSafeCalibration.run(
        dataset, thresholds: { relevance: 0.75 }, config: offline_config, evaluator: ->(*) { reports.shift }
      )
    end

    assert_includes output, "chat/openai/gpt-4o"
    assert_includes output, "system_one/typesafe/jev-1.13.0"
    assert_includes output, "threshold=0.750 labeled=3 expected_passes=1 scored=2 predicted_passes=2 missing_scores=1/3 labeled samples"
    assert_includes output, "accuracy=1/2 (50.0% of scored labels)"
    assert_includes output, "false_passes=1/2 (50.0% of labeled automatic passes)"
    assert_includes output, "false_passes=n/a (0 labeled automatic passes)"
    assert_includes output, "faithfulness         threshold=0.800 scored=3 missing_scores=0/3 samples quality=unknown"
  end

  def test_annotation_and_threshold_validation_happens_before_evaluation
    evaluator = ->(*) { flunk "evaluator must not run for invalid calibration input" }

    error = assert_raises(ArgumentError) do
      TypeSafeCalibration.run([sample("yes")], config: offline_config, evaluator:)
    end
    assert_includes error.message, "must be true or false"

    error = assert_raises(ArgumentError) do
      TypeSafeCalibration.run([sample(true)], thresholds: { relevance: 1.1 }, config: offline_config, evaluator:)
    end
    assert_includes error.message, "between 0.0 and 1.0"
  end

  private

  def report(score, escalated: nil)
    details = escalated.nil? ? {} : { relevance: { escalated: } }
    result = RubricLLM::Result.new(scores: { relevance: score }, details:, sample: { question: "synthetic question" })
    RubricLLM::Report.new(results: [result], duration: 0.01)
  end

  def sample(expected)
    { question: "synthetic question", answer: "synthetic answer", expected_judgments: { relevance: expected } }
  end

  def quality_report(scores, backend:, model:, escalations: nil)
    provider = backend == :chat ? :openai : :typesafe
    results = scores.each_with_index.map do |score, index|
      detail = { usage_attempts: [{ backend:, provider:, model:, usage: { input_tokens: 2, output_tokens: 1 } }] }
      detail[:escalated] = escalations[index] if escalations
      RubricLLM::Result.new(
        scores: { relevance: score, faithfulness: 0.5 }, details: { relevance: detail }, sample: { question: "q#{index}" }
      )
    end
    RubricLLM::Report.new(results:, duration: 0.01)
  end

  def offline_config
    RubricLLM::Config.new(typesafe_api_key: "offline", judge_backend: :chat)
  end
end
