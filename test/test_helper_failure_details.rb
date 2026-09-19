# frozen_string_literal: true

require "test_helper"
require "rubric_llm/minitest"
require "rubric_llm/rspec"

class FailureDetailsClient
  def initialize(probability:, confidence:)
    @probability = probability
    @confidence = confidence
  end

  def call(questions:, **)
    answers = questions.to_h do |question|
      if question.type == :score
        raw = {
          "type" => "score", "score" => 1.0, "confidence" => @confidence,
          "legend" => question.criteria.each_with_index.to_h { |level, index| [index.to_s, level] },
          "probabilities" => question.criteria.each_index.to_h { |index| [index.to_s, index == 1 ? 1.0 : 0.0] }
        }
        answer = RubricLLM::SystemOne::Answer::Score.new(raw, question)
      else
        answer = RubricLLM::SystemOne::Answer::Noul.new({ "type" => "noul", "noul" => @probability })
      end
      [question.id, answer]
    end
    RubricLLM::SystemOne::Response.new(
      answers:, usage: { "input_tokens" => 5, "output_tokens" => 2 }, model: "jev-test", latency_ms: 1.0,
      raw: { "private_payload" => "RAW_REQUEST_SENTINEL" }
    )
  end
end

class TestHelperFailureDetails < Minitest::Test
  include TestSetup
  include RubricLLM::Assertions

  def test_all_assertions_include_system_one_evidence
    with_provider(:system_one) do |config|
      assertions = [
        -> { assert_faithful("Answer.", ["Source."], config:) },
        -> { assert_correct("Answer.", "Reference.", config:) },
        -> { assert_relevant("Question?", "Answer.", config:) },
        -> { refute_hallucination("Answer.", ["Source."], config:) }
      ]
      assertions.each do |assertion|
        error = assert_raises(Minitest::Assertion, &assertion)

        assert_includes error.message, "backend=system_one"
        assert_includes error.message, "model=jev-test"
        assert_includes error.message, "probabilities="
        refute_includes error.message, "RAW_REQUEST_SENTINEL"
      end
    end
  end

  def test_correctness_failure_includes_confidence_and_contradiction
    with_provider(:system_one) do |config|
      error = assert_raises(Minitest::Assertion) { assert_correct("A", "B", config:) }

      assert_includes error.message, "confidence=0.9"
      assert_includes error.message, "contradiction_probability=0.1"
    end
  end

  def test_both_message_directions_for_all_matchers_include_evidence
    with_provider(:system_one) do |config|
      matchers = [
        RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["Source."]),
        RubricLLM::RSpecMatchers::CorrectnessMatcher.new("Reference."),
        RubricLLM::RSpecMatchers::RelevanceMatcher.new("Question?"),
        RubricLLM::RSpecMatchers::HallucinationMatcher.new(["Source."])
      ]
      matchers.each do |matcher|
        matcher.with_config(config).matches?("Answer.")
        [matcher.failure_message, matcher.failure_message_when_negated].each do |message|
          assert_includes message, "model=jev-test"
          assert_includes message, "probabilities="
          refute_includes message, "RAW_REQUEST_SENTINEL"
        end
      end
    end
  end

  def test_cascade_failure_shows_chat_reason_and_nested_typed_evidence
    with_provider(:cascade, confidence: 0.2) do |config|
      stub_judge_response('{"score": 0.2, "reasoning": "off topic"}')
      error = assert_raises(Minitest::Assertion) { assert_relevant("Question?", "Answer.", config:) }
      matcher = RubricLLM::RSpecMatchers::RelevanceMatcher.new("Question?").with_config(config)

      refute matcher.matches?("Answer.")
      [error.message, matcher.failure_message, matcher.failure_message_when_negated].each do |message|
        assert_includes message, "off topic"
        assert_includes message, "escalated=true"
        assert_includes message, "escalation_reason=confidence 0.2 below 0.7"
        assert_includes message, "System One attempt: backend=system_one, model=jev-test, confidence=0.2"
        assert_includes message, "probabilities="
        refute_includes message, "RAW_REQUEST_SENTINEL"
      end
    end
  end

  def test_failed_fallback_shows_error_and_original_evidence
    with_provider(:cascade, confidence: 0.2) do |config|
      RubyLLMStub.fake_chat = RubyLLMStub::FakeChat.new(fail_times: 1)
      error = assert_raises(Minitest::Assertion) { assert_relevant("Question?", "Answer.", config:) }

      assert_includes error.message, "got nil"
      assert_includes error.message, "fallback_error=Judge call failed: transient failure"
      assert_includes error.message, "escalation_reason=confidence 0.2 below 0.7"
      assert_includes error.message, "System One attempt:"
    end
  end

  def test_non_escalated_cascade_does_not_hide_false_decision
    with_provider(:cascade) do |config|
      error = assert_raises(Minitest::Assertion) { assert_relevant("Question?", "Answer.", config:) }

      assert_includes error.message, "escalated=false"
      refute_includes error.message, "System One attempt:"
    end
  end

  private

  def with_provider(backend, probability: 0.1, confidence: 0.9)
    client = FailureDetailsClient.new(probability:, confidence:)
    singleton = RubricLLM::SystemOne::Client.singleton_class
    singleton.define_method(:new) { |**| client }
    config = RubricLLM::Config.new(judge_backend: backend, typesafe_api_key: "offline", max_retries: 0)
    yield config
  ensure
    singleton.remove_method(:new)
  end
end
