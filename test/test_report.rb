# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestReport < Minitest::Test
  def setup
    @results = [
      RubricLLM::Result.new(
        scores: { faithfulness: 0.9, relevance: 0.8 },
        details: {},
        sample: { question: "q1", answer: "a1", context: [], ground_truth: nil }
      ),
      RubricLLM::Result.new(
        scores: { faithfulness: 0.7, relevance: 0.6 },
        details: {},
        sample: { question: "q2", answer: "a2", context: [], ground_truth: nil }
      ),
      RubricLLM::Result.new(
        scores: { faithfulness: 0.5, relevance: 0.9 },
        details: {},
        sample: { question: "q3", answer: "a3", context: [], ground_truth: nil }
      )
    ]
    @report = RubricLLM::Report.new(results: @results, duration: 2.5)
  end

  def test_metric_stats
    stats = @report.metric_stats

    assert_in_delta 0.7, stats[:faithfulness][:mean], 0.001
    assert_equal 3, stats[:faithfulness][:count]
    assert_in_delta 0.5, stats[:faithfulness][:min]
    assert_in_delta 0.9, stats[:faithfulness][:max]
  end

  def test_worst
    worst = @report.worst(1)

    assert_equal 1, worst.size
    assert_equal "q2", worst.first.sample[:question]
  end

  def test_failures
    failures = @report.failures(threshold: 0.8)

    assert_equal 2, failures.size
  end

  def test_summary
    summary = @report.summary

    assert_includes summary, "Samples: 3"
    assert_includes summary, "Duration: 2.5s"
    assert_includes summary, "faithfulness"
  end

  def test_export_csv
    Dir.mktmpdir do |dir|
      path = File.join(dir, "results.csv")
      @report.export_csv(path)
      content = File.read(path)

      assert_includes content, "question"
      assert_includes content, "faithfulness"
      lines = content.lines

      assert_equal 4, lines.size # header + 3 results
    end
  end

  def test_export_json
    Dir.mktmpdir do |dir|
      path = File.join(dir, "results.json")
      @report.export_json(path)
      data = JSON.parse(File.read(path))

      assert_equal 3, data["results"].size
      assert data["summary"]
    end
  end

  def test_to_json_returns_string
    json_string = @report.to_json
    data = JSON.parse(json_string)

    assert_instance_of String, json_string
    assert_equal 3, data["results"].size
    assert data["summary"]
  end

  def test_scores_for
    scores = @report.scores_for(:faithfulness)

    assert_equal [0.9, 0.7, 0.5], scores
  end

  def test_worst_sorts_nil_overall_to_end
    results_with_nil = [
      RubricLLM::Result.new(scores: { a: nil }, details: {}, sample: { question: "nil_q" }),
      RubricLLM::Result.new(scores: { a: 0.3 }, details: {}, sample: { question: "low_q" }),
      RubricLLM::Result.new(scores: { a: 0.9 }, details: {}, sample: { question: "high_q" })
    ]
    report = RubricLLM::Report.new(results: results_with_nil)
    worst = report.worst(1)

    assert_equal "low_q", worst.first.sample[:question]
  end
end
