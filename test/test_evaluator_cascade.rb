# frozen_string_literal: true

require "test_helper"

class TestEvaluatorCascade < Minitest::Test
  include TestSetup

  class CountingCascadeMetric
    class << self
      attr_accessor :system_one_calls, :chat_calls
    end

    def initialize(judge:); end

    def call_system_one(**)
      self.class.system_one_calls += 1
      { score: 0.7, details: { backend: :system_one, usage: { input_tokens: 1, output_tokens: 1 } } }
    end

    def call_chat(**)
      self.class.chat_calls += 1
      { score: 0.9, details: { backend: :chat, usage: nil } }
    end
  end

  def test_evaluator_runs_cascade_metric_once_without_chat_when_no_response_requires_escalation
    CountingCascadeMetric.system_one_calls = 0
    CountingCascadeMetric.chat_calls = 0
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "offline")

    result = RubricLLM::Evaluator.new(config:, metrics: [CountingCascadeMetric]).call(question: "q", answer: "a")

    assert_in_delta 0.7, result.scores[:counting_cascade_metric]
    assert_equal 1, CountingCascadeMetric.system_one_calls
    assert_equal 0, CountingCascadeMetric.chat_calls
  end

  def test_evaluator_retains_paid_usage_when_chat_response_is_malformed
    tokens = RubyLLMTokens.new(input: 8, output: 2)
    RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(response_content: "not json", response_tokens: tokens)
    config = RubricLLM::Config.new(max_retries: 0)

    result = RubricLLM.evaluate(question: "q", answer: "a", metrics: [RubricLLM::Metrics::Relevance], config:)

    assert_equal({ input_tokens: 8, output_tokens: 2 }, result.details.dig(:relevance, :usage))
  end
end
