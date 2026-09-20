# frozen_string_literal: true

require "test_helper"

class TestTypeSafeUsage < Minitest::Test
  include TestSetup

  class RetryTransport
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def call(**)
      @calls += 1
      raise Net::ReadTimeout if @calls == 1

      body = JSON.generate(
        model: "jev-1.13.0", answers: { "sentence_0" => { type: "noul", noul: 0.99 } },
        usage: { input_tokens: 10, output_tokens: 2 }
      )
      Struct.new(:code, :body).new("200", body)
    end
  end

  def test_system_one_preserves_unknown_usage_after_timeout_then_success
    assert_retry_usage(:system_one)
  end

  def test_cascade_preserves_unknown_usage_after_timeout_then_success
    assert_retry_usage(:cascade)
  end

  private

  def assert_retry_usage(backend)
    config = RubricLLM::Config.new(judge_backend: backend, typesafe_api_key: "offline", max_retries: 1, retry_base_delay: 0)
    transport = RetryTransport.new
    client = RubricLLM::SystemOne::Client.new(config:, transport:)
    system_one = RubricLLM::Judges::SystemOne.new(config:, client:)
    judge = backend == :cascade ? RubricLLM::Judges::Cascade.new(config:, system_one:) : system_one
    metric = RubricLLM::Metrics::Faithfulness.new(judge:)

    result = metric.call(question: "q", answer: "a", context: ["c"])
    summary = RubricLLM::UsageSummary.new(judge.usage_attempts)

    assert_in_delta 0.99, result[:score]
    assert_equal 2, transport.calls
    assert_equal 2, judge.usage_attempts.length
    assert_nil judge.usage_attempts.first[:usage]
    assert_nil summary.total
    refute_predicate summary, :complete?
    assert_equal({ "input_tokens" => 10, "output_tokens" => 2 }, judge.usage_attempts.last[:usage])
  end
end
