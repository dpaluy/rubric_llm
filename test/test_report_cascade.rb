# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TestReportCascade < Minitest::Test
  def test_escalations_appear_in_summary_and_exports
    results = [
      RubricLLM::Result.new(scores: { relevance: 0.8 }, details: { relevance: { escalated: true } }, sample: { question: "q1" }),
      RubricLLM::Result.new(scores: { relevance: 0.9 }, details: { relevance: { escalated: false } }, sample: { question: "q2" })
    ]
    report = RubricLLM::Report.new(results:)

    assert_includes report.summary, "escalated: 1/2 (50.0%)"
    assert_equal({ escalated: 1, total: 2, rate: 0.5 }, report.escalation_stats[:relevance])
    assert_equal 1, JSON.parse(report.to_json).dig("escalations", "relevance", "escalated")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "cascade.csv")
      report.export_csv(path)

      assert_includes File.read(path), "relevance_escalated"
    end
  end

  def test_all_failed_cascade_metric_keeps_escalation_visible_in_summary_and_exports
    result = RubricLLM::Result.new(
      scores: { relevance: nil },
      details: { relevance: { error: "fallback failed", escalated: true } },
      sample: { question: "q", answer: "a" }
    )
    report = RubricLLM::Report.new(results: [result])

    assert_includes report.summary, "relevance             escalated: 1/1 (100.0%)"
    assert_equal 1, JSON.parse(report.to_json).dig("escalations", "relevance", "escalated")

    Dir.mktmpdir do |dir|
      path = File.join(dir, "failed.csv")
      report.export_csv(path)

      assert_includes File.read(path), "relevance_escalated"
    end
  end

  def test_usage_adds_system_one_and_chat_fallback_tokens
    result = RubricLLM::Result.new(
      scores: { relevance: 0.8 },
      details: {
        relevance: {
          usage: { input_tokens: 7, output_tokens: 2 },
          system_one: { usage: { "input_tokens" => 3, "output_tokens" => 1 } }
        }
      }
    )
    report = RubricLLM::Report.new(results: [result])

    assert_equal({ input_tokens: 10, output_tokens: 3 }, report.total_usage)
    assert_predicate report, :usage_complete?
  end

  def test_usage_ignores_non_token_server_tool_counters
    tokens = RubyLLMTokens.new(
      input: 10, output: 5, server_tool_use: { "web_search_requests" => 0 }
    )
    result = RubricLLM::Result.new(scores: { relevance: 0.8 }, details: { relevance: { usage: tokens.to_h } })

    assert_equal({ input_tokens: 10, output_tokens: 5 }, RubricLLM::Report.new(results: [result]).total_usage)
  end

  def test_mixed_known_and_unknown_usage_is_not_presented_as_complete
    results = [
      RubricLLM::Result.new(scores: { relevance: 0.8 }, details: { relevance: { usage: { input_tokens: 10 } } }),
      RubricLLM::Result.new(scores: { relevance: nil }, details: { relevance: { usage: nil } })
    ]
    report = RubricLLM::Report.new(results:)

    assert_nil report.total_usage
    refute_predicate report, :usage_complete?
    refute JSON.parse(report.to_json)["usage_complete"]
  end

  def test_real_empty_tokens_are_unknown
    usage = RubyLLMTokens.new.to_h
    result = RubricLLM::Result.new(scores: { relevance: 0.8 }, details: { relevance: { usage: } })
    report = RubricLLM::Report.new(results: [result])

    assert_nil report.total_usage
    refute_predicate report, :usage_complete?
  end
end
