# frozen_string_literal: true

require_relative "helper"
require "rubric_llm/minitest"
require "tmpdir"
require "csv"
require "timeout"

class EvaluationContract < RealClientContract
  include RubricLLM::Assertions

  def test_single_evaluation_preserves_score_details_and_sample
    stub_response
    result = RubricLLM.evaluate(question: "Question", answer: "Answer", config: configuration,
                                metrics: [RubricLLM::Metrics::Relevance])

    assert_equal({ relevance: 0.9 }, result.scores)
    assert_equal({ relevance: { reasoning: "offline" } }, result.details)
    assert_equal "Question", result.sample[:question]
    assert_in_delta 0.9, result.overall
    assert_predicate result, :valid?
    assert_predicate result, :pass?
  end

  def test_single_evaluation_preserves_error_shape
    stub_response(content: "invalid")
    result = RubricLLM.evaluate(question: "Question", answer: "Answer", config: configuration,
                                metrics: [RubricLLM::Metrics::Relevance])

    assert_nil result.scores[:relevance]
    assert_nil result.overall
    refute_predicate result, :pass?
    refute_predicate result, :valid?
    assert_includes result.errors[:relevance], "Judge response was not valid JSON"
    assert_equal result.errors[:relevance], result.details.dig(:relevance, :error)
  end

  def test_batch_order_errors_and_exports_with_real_client
    stub_response(content: '{"score":0.9,"reasoning":"first"}')
    stub_response(content: "invalid")
    stub_response(content: '{"score":0.4,"reasoning":"third"}')
    dataset = %w[first second third].map { |question| { question:, answer: "Answer" } }
    report = RubricLLM.evaluate_batch(dataset, config: configuration, metrics: [RubricLLM::Metrics::Relevance])

    assert_equal(%w[first second third], report.results.map { |result| result.sample[:question] })
    assert_equal [0.9, nil, 0.4], report.scores_for(:relevance)
    assert_equal 2, report.failures.size
    assert_equal 2, report.metric_stats.dig(:relevance, :count)
    assert_equal 3, @requests.size
    verify_exports(report)
  end

  def test_assertion_uses_real_client_for_success_and_failure
    stub_response

    assert_relevant("Question", "Answer", config: configuration)
    stub_response(content: '{"score":0.2,"reasoning":"irrelevant"}')
    error = assert_raises(Minitest::Assertion) { assert_relevant("Question", "Answer", config: configuration) }

    assert_includes error.message, "Expected relevance >= 0.8, got 0.2"
    assert_includes error.message, "irrelevant"
  end

  def test_threaded_batch_retains_input_order_when_requests_finish_in_reverse
    release = Queue.new
    completed = []
    @stubs.post("https://openai.invalid/v1/responses") do |env|
      first = JSON.parse(env.body).dig("input", 0, "content").include?("first")
      if first
        Timeout.timeout(2) { release.pop }
        completed << "first"
      else
        completed << "second"
        release << true
      end
      response_fixture(content: JSON.generate(score: first ? 0.9 : 0.4))
    end
    dataset = %w[first second].map { |question| { question:, answer: "Answer" } }
    report = RubricLLM.evaluate_batch(dataset, config: configuration, concurrency: 2, metrics: [RubricLLM::Metrics::Relevance])

    assert_equal %w[second first], completed
    assert_equal(%w[first second], report.results.map { |result| result.sample[:question] })
    assert_equal [0.9, 0.4], report.scores_for(:relevance)
  end

  private

  def verify_exports(report)
    Dir.mktmpdir("rubric-contract") do |directory|
      json_path = File.join(directory, "report.json")
      csv_path = File.join(directory, "report.csv")
      report.export_json(json_path)
      report.export_csv(csv_path)
      exported = JSON.parse(File.read(json_path))
      rows = CSV.read(csv_path, headers: true)

      assert_equal([0.9, nil, 0.4], exported.fetch("results").map { |result| result.dig("scores", "relevance") })
      assert_equal({ "relevance" => 1 }, exported.fetch("errors"))
      assert_includes exported.dig("results", 1, "errors", "relevance"), "Judge response was not valid JSON"
      assert_equal(%w[first second third], rows.map { |row| row["question"] })
      assert_equal(["0.9", nil, "0.4"], rows.map { |row| row["relevance"] })
      assert_equal exported, JSON.parse(report.to_json)
    end
  end
end
