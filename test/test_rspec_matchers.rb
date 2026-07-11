# frozen_string_literal: true

require "test_helper"
require "rubric_llm/rspec"

# Tests for RSpec matchers using Minitest (no rspec dependency needed).
# Each matcher is a plain Ruby object with matches?, failure_message, etc.
class TestRSpecMatchers < Minitest::Test
  include TestSetup

  # --- FaithfulnessMatcher ---

  def test_faithfulness_matcher_passes
    stub_judge_response('{"score": 0.9, "claims": [], "reasoning": "faithful"}')
    matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["Paris is the capital of France."])

    assert matcher.matches?("Paris is the capital.")
  end

  def test_faithfulness_matcher_fails_below_threshold
    stub_judge_response('{"score": 0.5, "claims": [], "reasoning": "unfaithful"}')
    matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["Paris is the capital."])

    refute matcher.matches?("Tokyo is the capital.")
    assert_includes matcher.failure_message, "faithfulness >= 0.8"
    assert_includes matcher.failure_message, "0.5"
  end

  def test_faithfulness_matcher_custom_threshold
    stub_judge_response('{"score": 0.85, "claims": [], "reasoning": "ok"}')
    matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["context"]).with_threshold(0.9)

    refute matcher.matches?("answer")
    assert_includes matcher.failure_message, "0.9"
  end

  def test_faithfulness_matcher_raises_for_empty_judge_response
    stub_judge_response("")
    matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["context"]).with_config(no_retry_config)

    error = assert_raises(RubricLLM::JudgeError) { matcher.matches?("answer") }
    assert_includes error.message, "empty"
  end

  def test_faithfulness_negated_message
    stub_judge_response('{"score": 0.95, "claims": [], "reasoning": "good"}')
    matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["context"])
    matcher.matches?("answer")

    assert_includes matcher.failure_message_when_negated, "faithfulness < 0.8"
  end

  # --- CorrectnessMatcher ---

  def test_correctness_matcher_passes
    stub_judge_response('{"score": 0.95, "reasoning": "matches"}')
    matcher = RubricLLM::RSpecMatchers::CorrectnessMatcher.new("Paris")

    assert matcher.matches?("Paris")
  end

  def test_correctness_matcher_fails
    stub_judge_response('{"score": 0.3, "reasoning": "wrong"}')
    matcher = RubricLLM::RSpecMatchers::CorrectnessMatcher.new("Paris")

    refute matcher.matches?("Tokyo")
    assert_includes matcher.failure_message, "correctness >= 0.8"
  end

  def test_correctness_negated_message
    stub_judge_response('{"score": 0.95, "reasoning": "matches"}')
    matcher = RubricLLM::RSpecMatchers::CorrectnessMatcher.new("Paris")
    matcher.matches?("Paris")

    assert_includes matcher.failure_message_when_negated, "correctness < 0.8"
  end

  # --- RelevanceMatcher ---

  def test_relevance_matcher_passes
    stub_judge_response('{"score": 0.9, "reasoning": "relevant"}')
    matcher = RubricLLM::RSpecMatchers::RelevanceMatcher.new("What is Ruby?")

    assert matcher.matches?("Ruby is a programming language.")
  end

  def test_relevance_matcher_fails
    stub_judge_response('{"score": 0.2, "reasoning": "off topic"}')
    matcher = RubricLLM::RSpecMatchers::RelevanceMatcher.new("What is Ruby?")

    refute matcher.matches?("The weather is nice.")
    assert_includes matcher.failure_message, "relevance >= 0.8"
  end

  def test_relevance_negated_message
    stub_judge_response('{"score": 0.9, "reasoning": "relevant"}')
    matcher = RubricLLM::RSpecMatchers::RelevanceMatcher.new("What is Ruby?")
    matcher.matches?("Ruby is a language.")

    assert_includes matcher.failure_message_when_negated, "relevance < 0.8"
  end

  # --- HallucinationMatcher ---

  def test_hallucination_matcher_detects_hallucination
    stub_judge_response('{"score": 0.3, "claims": [], "reasoning": "not supported"}')
    matcher = RubricLLM::RSpecMatchers::HallucinationMatcher.new(["Paris is the capital."])

    assert matcher.matches?("Tokyo is the capital.")
  end

  def test_hallucination_matcher_no_hallucination
    stub_judge_response('{"score": 0.95, "claims": [], "reasoning": "faithful"}')
    matcher = RubricLLM::RSpecMatchers::HallucinationMatcher.new(["Paris is the capital."])

    refute matcher.matches?("Paris is the capital.")
    assert_includes matcher.failure_message, "hallucination"
  end

  def test_hallucination_matcher_raises_for_empty_judge_response
    stub_judge_response("")
    matcher = RubricLLM::RSpecMatchers::HallucinationMatcher.new(["context"]).with_config(no_retry_config)

    error = assert_raises(RubricLLM::JudgeError) { matcher.matches?("answer") }
    assert_includes error.message, "empty"
  end

  def test_hallucination_negated_message
    stub_judge_response('{"score": 0.3, "claims": [], "reasoning": "not supported"}')
    matcher = RubricLLM::RSpecMatchers::HallucinationMatcher.new(["context"])
    matcher.matches?("answer")

    assert_includes matcher.failure_message_when_negated, "no hallucination"
  end

  # --- with_config ---

  def test_matcher_accepts_custom_config
    stub_judge_response('{"score": 0.9, "reasoning": "ok"}')
    custom = RubricLLM::Config.new(judge_model: "claude-haiku-4-5", judge_provider: :anthropic)
    matcher = RubricLLM::RSpecMatchers::RelevanceMatcher.new("question").with_config(custom)

    assert matcher.matches?("answer")
    assert_equal custom, matcher.config
  end

  # --- DSL helpers ---

  def test_dsl_helpers_exist
    obj = Object.new
    obj.extend(RubricLLM::RSpecMatchers)

    assert_respond_to obj, :be_faithful_to
    assert_respond_to obj, :be_correct_for
    assert_respond_to obj, :be_relevant_to
    assert_respond_to obj, :hallucinate_from
  end

  private

  def no_retry_config
    RubricLLM::Config.new(max_retries: 0, retry_base_delay: 0.0)
  end
end
