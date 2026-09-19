# frozen_string_literal: true

require "test_helper"

class TestCascadeCorrectnessConflicts < Minitest::Test
  include TestSetup

  SAMPLE = { question: "What is the capital of France?", answer: "Berlin", ground_truth: "Paris" }.freeze

  class SystemOneRunner
    attr_reader :calls, :last_response

    def initialize(correctness_score:, contradiction:)
      @correctness_score = correctness_score
      @contradiction = contradiction
      @calls = 0
    end

    def call(questions:, **)
      @calls += 1
      answers = questions.to_h do |question|
        raw = if question.type == :score
                score = question.id == "correctness" ? @correctness_score : 4.0
                probabilities = Array.new(question.criteria.length, 0.0)
                probabilities[score.to_i] = 1.0
                {
                  "type" => "score", "score" => score,
                  "legend" => question.criteria.each_with_index.to_h { |level, index| [index.to_s, level] },
                  "probabilities" => probabilities.each_with_index.to_h { |value, index| [index.to_s, value] },
                  "confidence" => 0.95
                }
              else
                { "type" => "noul", "noul" => question.id == "contradiction" ? @contradiction : 0.1 }
              end
        answer = if question.type == :score
                   RubricLLM::SystemOne::Answer::Score.new(raw, question)
                 else
                   RubricLLM::SystemOne::Answer::Noul.new(raw)
                 end
        [question.id, answer]
      end
      usage = { "input_tokens" => 3, "output_tokens" => 1 }
      @last_response = RubricLLM::SystemOne::Response.new(
        answers:, usage:, model: "jev-offline", latency_ms: 2.0,
        raw: { "model" => "jev-offline", "answers" => answers.transform_values(&:raw), "usage" => usage }
      )
    end
  end

  def test_conflict_escalates_through_chat_and_preserves_system_one_evidence
    chat = RubyLLMStub::FakeChat.new(
      response_content: '{"score": 0.91, "reasoning": "chat review"}',
      response_tokens: RubyLLMTokens.new(input: 7, output: 2)
    )
    result, system_one, = run_correctness(score: 3.2, contradiction: 0.9, chat:)
    evidence = result[:details][:system_one]

    assert_equal 1, system_one.calls
    assert_equal 1, chat.call_count
    assert_in_delta 0.91, result[:score]
    assert result[:details][:escalated]
    assert_match(/correctness.*contradiction/, result[:details][:escalation_reason])
    assert_in_delta 3.2, evidence[:score]
    assert_in_delta 0.9, evidence[:contradiction_probability]
    assert_equal "jev-offline", evidence[:model]
    assert_equal({ "input_tokens" => 3, "output_tokens" => 1 }, evidence[:usage])
    assert_in_delta 3.2, evidence.dig(:raw_answers, "correctness", "score")
    assert_in_delta 0.9, evidence.dig(:raw_answers, "contradiction", "noul")
    assert_equal({ input_tokens: 7, output_tokens: 2 }, result[:details][:usage])
    assert_equal "chat review", result[:details][:reasoning]
  end

  def test_high_score_with_low_contradiction_stays_cheap
    result, _, chat = run_correctness(score: 4.0, contradiction: 0.2)

    assert_in_delta 1.0, result[:score]
    refute result[:details][:escalated]
    assert_equal 0, chat.call_count
  end

  def test_low_score_with_high_contradiction_stays_cheap
    result, _, chat = run_correctness(score: 2.0, contradiction: 0.9)

    assert_in_delta 0.5, result[:score]
    refute result[:details][:escalated]
    assert_equal 0, chat.call_count
  end

  def test_score_at_point_seventy_five_escalates_when_contradiction_exceeds_band
    result, _, chat = run_correctness(score: 3.0, contradiction: 0.66)

    assert result[:details][:escalated]
    assert_equal 1, chat.call_count
  end

  def test_contradiction_at_uncertainty_band_boundary_keeps_existing_escalation
    result, _, chat = run_correctness(score: 3.0, contradiction: 0.65)

    assert result[:details][:escalated]
    assert_match(/noul probability 0.65 inside/, result[:details][:escalation_reason])
    assert_equal 1, chat.call_count
  end

  def test_custom_policy_true_and_false_override_default_conflict_rule
    [true, false].each do |decision|
      seen = []
      policy = lambda do |response|
        seen << response
        decision
      end
      result, system_one, chat = run_correctness(score: 4.0, contradiction: 0.9, cascade_policy: policy)

      assert_equal decision, result[:details][:escalated]
      if decision
        assert_equal "custom policy", result[:details][:escalation_reason]
      else
        assert_nil result[:details][:escalation_reason]
      end

      assert_equal decision ? 1 : 0, chat.call_count
      assert_same system_one.last_response, seen.fetch(0)
    end
  end

  def test_high_score_on_an_unrelated_metric_does_not_use_correctness_conflict_rule
    chat = RubyLLMStub::FakeChat.new
    RubyLLMStub.fake_chat = chat
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "offline")
    cascade = RubricLLM::Judges::Cascade.new(
      config:, system_one: SystemOneRunner.new(correctness_score: 4.0, contradiction: 0.9)
    )
    result = RubricLLM::Metrics::Relevance.new(judge: cascade).call(question: "q", answer: "a")

    assert_in_delta 1.0, result[:score]
    refute result[:details][:escalated]
    assert_equal 0, chat.call_count
  end

  def test_failed_chat_fallback_keeps_conflict_reason_and_error
    chat = RubyLLMStub::FakeChat.new(fail_times: 1)
    result, = run_correctness(score: 4.0, contradiction: 0.9, chat:, max_retries: 0)

    assert_nil result[:score]
    assert result[:details][:escalated]
    assert_match(/correctness.*contradiction/, result[:details][:escalation_reason])
    assert_match(/Judge call failed: transient failure/, result[:details][:fallback_error])
    assert_in_delta 4.0, result.dig(:details, :system_one, :score)
    assert_in_delta 0.9, result.dig(:details, :system_one, :contradiction_probability)
  end

  private

  def run_correctness(score:, contradiction:, chat: RubyLLMStub::FakeChat.new, cascade_policy: nil, max_retries: 2)
    RubyLLMStub.fake_chat = chat
    config = RubricLLM::Config.new(
      judge_backend: :cascade, typesafe_api_key: "offline", cascade_policy:, max_retries:
    )
    system_one = SystemOneRunner.new(correctness_score: score, contradiction:)
    cascade = RubricLLM::Judges::Cascade.new(config:, system_one:)
    result = RubricLLM::Metrics::Correctness.new(judge: cascade).call(**SAMPLE)
    [result, system_one, chat]
  end
end
