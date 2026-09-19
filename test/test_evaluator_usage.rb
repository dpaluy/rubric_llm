# frozen_string_literal: true

require "test_helper"

class TestEvaluatorUsage < Minitest::Test
  include TestSetup

  class LegacyMetric < RubricLLM::Metrics::Base
    def call(**)
      response = judge_eval(system_prompt: "legacy", user_prompt: "legacy")
      { score: response.fetch("score"), details: {} }
    end
  end

  class TwoCallMetric < LegacyMetric
    def call(**)
      super
      super
    end
  end

  class NoCallFailure < LegacyMetric
    def call(**)
      raise RubricLLM::JudgeError, "failed before requesting a judgment"
    end
  end

  def test_error_before_a_call_does_not_reuse_previous_metric_usage
    stub_tokens
    report = evaluate([RubricLLM::Metrics::Relevance, NoCallFailure])

    assert_equal({ input_tokens: 10, output_tokens: 2 }, report.total_usage)
    assert_predicate report, :usage_complete?
    assert_empty report.results.first.details.dig(:no_call_failure, :usage_attempts)
    assert_nil report.results.first.details.dig(:no_call_failure, :usage)
  end

  def test_usage_includes_legacy_metric_without_usage_details
    stub_tokens
    report = evaluate([RubricLLM::Metrics::Relevance, LegacyMetric])

    assert_equal({ input_tokens: 20, output_tokens: 4 }, report.total_usage)
    assert_predicate report, :usage_complete?
  end

  def test_usage_includes_every_call_in_a_custom_metric
    stub_tokens
    report = evaluate([TwoCallMetric])

    assert_equal({ input_tokens: 20, output_tokens: 4 }, report.total_usage)
    assert_equal 2, report.usage_by_model.first[:calls]
    assert_equal "gpt-4o", report.usage_by_model.first[:model]
    assert_equal :openai, report.usage_by_model.first[:provider]
  end

  def test_unknown_legacy_usage_makes_total_incomplete
    report = evaluate([LegacyMetric])

    assert_nil report.total_usage
    refute_predicate report, :usage_complete?
    refute JSON.parse(report.to_json)["usage_complete"]
  end

  def test_incomplete_provider_usage_is_not_a_complete_total
    tokens = RubyLLMTokens.new(input: 10)
    RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(response_tokens: tokens)
    report = evaluate([LegacyMetric])

    assert_nil report.total_usage
    refute_predicate report, :usage_complete?
  end

  def test_malformed_reply_retains_its_model_and_tokens
    stub_tokens
    RubyLLMStub.chat.response_content = "not json"
    report = evaluate([LegacyMetric])

    assert_nil report.results.first.scores[:legacy_metric]
    assert_equal({ input_tokens: 10, output_tokens: 2 }, report.total_usage)
    assert_equal "gpt-4o", JSON.parse(report.to_json).fetch("usage_by_model").first.fetch("model")
  end

  private

  def stub_tokens
    tokens = RubyLLMTokens.new(input: 10, output: 2)
    RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(response_tokens: tokens)
  end

  def evaluate(metrics)
    RubricLLM.evaluate_batch([{ question: "q", answer: "a" }], metrics:, config: RubricLLM::Config.new)
  end
end
