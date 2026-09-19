# frozen_string_literal: true

require "test_helper"

class TestCascadeCompatibility < Minitest::Test
  include TestSetup

  class LegacyMetric < RubricLLM::Metrics::Base
    def call(**)
      raise "fallback backend must be chat" unless backend == :chat

      response = judge_eval(system_prompt: "legacy", user_prompt: "legacy")
      { score: response.fetch("score"), details: {} }
    end

    def call_system_one(**)
      raise RubricLLM::JudgeError, "offline failure"
    end
  end

  def test_custom_metric_with_call_and_system_one_falls_back_without_call_chat
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "offline")
    result = RubricLLM.evaluate(question: "q", answer: "a", metrics: [LegacyMetric], config:)

    assert_in_delta 0.9, result.scores[:legacy_metric]
    assert result.details.dig(:legacy_metric, :escalated)
    assert_equal :cascade, config.judge_backend
  end

  def test_missing_context_is_not_a_cascade_attempt
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "offline")
    report = RubricLLM.evaluate_batch([{ question: "q", answer: "a" }], metrics: [RubricLLM::Metrics::Faithfulness], config:)

    assert_empty report.escalation_stats
    refute report.results.first.details[:faithfulness].key?(:escalated)
  end

  def test_empty_sentences_are_not_cascade_attempts
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "offline")
    report = RubricLLM.evaluate_batch([{ question: "q", answer: " ", context: ["c"] }],
                                      metrics: [RubricLLM::Metrics::Faithfulness], config:)

    assert_empty report.escalation_stats
  end

  def test_skipped_samples_do_not_dilute_fallback_rate
    answer = RubricLLM::SystemOne::Answer::Noul.new("type" => "noul", "noul" => 0.5)
    response = RubricLLM::SystemOne::Response.new(answers: { "sentence_0" => answer }, model: "jev-1.13.0",
                                                  usage: { "input_tokens" => 3, "output_tokens" => 1 }, latency_ms: 1, raw: {})
    client = Object.new
    client.define_singleton_method(:call) { |**| response }
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "offline")
    dataset = [["c"], [], []].map { |context| { question: "q", answer: "a", context: } }

    cascade = RubricLLM::Judges::Cascade.new(config:, system_one: client)
    metric = RubricLLM::Metrics::Faithfulness.new(judge: cascade)
    results = dataset.map do |sample|
      result = metric.call(**sample)
      RubricLLM::Result.new(scores: { faithfulness: result[:score] }, details: { faithfulness: result[:details] })
    end
    report = RubricLLM::Report.new(results:)

    assert_equal({ escalated: 1, total: 1, rate: 1.0 }, report.escalation_stats[:faithfulness])
    assert_includes report.summary, "escalated: 1/1 (100.0%)"
  end
end
