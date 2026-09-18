# frozen_string_literal: true

require "test_helper"

class TestCascade < Minitest::Test
  FakeAnswer = Struct.new(:confidence, :probability)
  FakeScore = Struct.new(:confidence, :score, :legend, :probabilities, :raw) do
    def normalized
      score / 4.0
    end
  end

  class Runner
    attr_reader :calls

    def initialize(response: nil, error: nil)
      @response = response
      @error = error
      @calls = 0
    end

    def call(**)
      @calls += 1
      raise @error if @error

      @response
    end
  end

  class Metric
    attr_reader :judge

    def initialize(judge:, chat_error: nil)
      @judge = judge
      @chat_error = chat_error
    end

    def call_system_one(**)
      response = judge.call(state: "state", questions: [:question])
      { score: 0.25, details: { backend: :system_one, usage: response.usage, raw_response: response.raw } }
    end

    def call_chat(**)
      raise @chat_error if @chat_error

      { score: 0.9, details: { backend: :chat, usage: { input_tokens: 7, output_tokens: 2 } } }
    end
  end

  def test_does_not_escalate_confident_response
    cascade = cascade_for(answer: FakeAnswer.new(0.9, nil))
    result = cascade.evaluate_metric(Metric.new(judge: cascade), {})

    assert_in_delta 0.25, result[:score]
    refute result[:details][:escalated]
  end

  def test_escalates_low_confidence
    cascade = cascade_for(answer: FakeAnswer.new(0.2, nil))
    result = cascade.evaluate_metric(Metric.new(judge: cascade), {})

    assert_in_delta 0.9, result[:score]
    assert result[:details][:escalated]
    assert_match(/confidence/, result[:details][:escalation_reason])
    assert_equal({ "input_tokens" => 3, "output_tokens" => 1 }, result[:details].dig(:system_one, :usage))
  end

  def test_escalates_uncertain_noul
    cascade = cascade_for(answer: FakeAnswer.new(nil, 0.5))

    assert cascade.evaluate_metric(Metric.new(judge: cascade), {})[:details][:escalated]
  end

  def test_custom_policy_receives_real_response
    seen = nil
    policy = lambda do |response|
      seen = response
      true
    end
    config = config(cascade_policy: policy)
    response = response_for(FakeAnswer.new(0.99, nil))
    cascade = RubricLLM::Judges::Cascade.new(config:, system_one: Runner.new(response:), chat: fake_chat)

    assert cascade.evaluate_metric(Metric.new(judge: cascade), {})[:details][:escalated]
    assert_same response, seen
  end

  def test_direct_builtin_metric_call_uses_cascade_system_one_backend
    runner = Runner.new(response: response_for(FakeScore.new(0.9, 3.2, {}, {}, {}), answer_id: "relevance"))
    cascade = RubricLLM::Judges::Cascade.new(config:, system_one: runner, chat: fake_chat)
    metric = RubricLLM::Metrics::Relevance.new(judge: cascade)

    result = metric.call(question: "q", answer: "a")

    assert_equal 1, runner.calls
    assert_in_delta 0.8, result[:score]
    refute result[:details][:escalated]
  end

  def test_paid_malformed_fallback_usage_is_retained_and_not_reused
    runner = Runner.new(response: response_for(FakeScore.new(0.2, 1.0, {}, {}, {}), answer_id: "relevance"))
    cascade = RubricLLM::Judges::Cascade.new(config: config(max_retries: 0), system_one: runner)
    tokens = RubyLLMTokens.new(input: 11, output: 4)
    RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(response_content: "not json", response_tokens: tokens)
    metric = RubricLLM::Metrics::Relevance.new(judge: cascade)

    malformed = metric.call(question: "q", answer: "a")

    assert_equal({ input_tokens: 11, output_tokens: 4 }, malformed[:details][:usage])
    RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(fail_times: 1)
    transport_failure = metric.call(question: "q", answer: "a")

    assert_nil transport_failure[:details][:usage]
  end

  def test_system_one_and_fallback_errors_remain_auditable
    cascade = RubricLLM::Judges::Cascade.new(
      config: config, system_one: Runner.new(error: RubricLLM::JudgeError.new("jev failed")), chat: fake_chat
    )
    metric = Metric.new(judge: cascade, chat_error: RubricLLM::JudgeError.new("chat failed"))
    result = cascade.evaluate_metric(metric, {})

    assert_nil result[:score]
    assert result[:details][:escalated]
    assert_equal "chat failed", result[:details][:fallback_error]
    assert_equal "jev failed", result[:details].dig(:system_one, :error)
  end

  private

  def cascade_for(answer:)
    RubricLLM::Judges::Cascade.new(config: config, system_one: Runner.new(response: response_for(answer)), chat: fake_chat)
  end

  def response_for(answer, answer_id: "q")
    RubricLLM::SystemOne::Response.new(
      answers: { answer_id => answer }, usage: { "input_tokens" => 3, "output_tokens" => 1 }, model: "jev-1.2.3",
      latency_ms: 4.0, raw: { "answers" => {} }
    )
  end

  def config(**)
    RubricLLM::Config.new(typesafe_api_key: "secret", judge_backend: :cascade, **)
  end

  def fake_chat
    RubricLLM::Judges::Chat.new(config: config)
  end
end
