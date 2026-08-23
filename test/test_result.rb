# frozen_string_literal: true

require "test_helper"

class TestResult < Minitest::Test
  def test_overall_mean
    result = RubricLLM::Result.new(
      scores: { faithfulness: 0.8, relevance: 0.9, correctness: 1.0 },
      details: {}
    )

    assert_in_delta 0.9, result.overall
  end

  def test_overall_with_nil_scores
    result = RubricLLM::Result.new(
      scores: { faithfulness: 0.8, relevance: nil },
      details: {}
    )

    assert_in_delta 0.8, result.overall
  end

  def test_overall_all_nil
    result = RubricLLM::Result.new(scores: { faithfulness: nil }, details: {})

    assert_nil result.overall
  end

  def test_default_threshold_constant_is_pass_default
    assert_in_delta(0.8, RubricLLM::DEFAULT_THRESHOLD)

    below = RubricLLM::Result.new(scores: { a: 0.79 }, details: {})

    refute_predicate below, :pass?

    boundary = RubricLLM::Result.new(scores: { a: RubricLLM::DEFAULT_THRESHOLD }, details: {})

    assert_predicate boundary, :pass?
  end

  def test_pass_above_threshold
    result = RubricLLM::Result.new(scores: { a: 0.9 }, details: {})

    assert result.pass?(threshold: 0.8)
  end

  def test_pass_below_threshold
    result = RubricLLM::Result.new(scores: { a: 0.5 }, details: {})

    refute result.pass?(threshold: 0.8)
  end

  def test_method_missing_for_scores
    result = RubricLLM::Result.new(scores: { faithfulness: 0.85 }, details: {})

    assert_in_delta 0.85, result.faithfulness
  end

  def test_respond_to_missing
    result = RubricLLM::Result.new(scores: { faithfulness: 0.85 }, details: {})

    assert_respond_to result, :faithfulness
    refute_respond_to result, :nonexistent
  end

  def test_to_h
    result = RubricLLM::Result.new(scores: { a: 0.9 }, details: { a: { note: "ok" } })
    hash = result.to_h

    assert_equal({ a: 0.9 }, hash[:scores])
    assert_in_delta 0.9, hash[:overall]
    assert_equal({}, hash[:errors])
  end

  def test_all_nil_scores_are_invalid_and_fail
    result = RubricLLM::Result.new(
      scores: { faithfulness: nil },
      details: { faithfulness: { error: "judge timeout" } }
    )

    assert_nil result.overall
    refute_predicate result, :pass?
    refute_predicate result, :valid?
    assert_equal({ faithfulness: "judge timeout" }, result.errors)
  end

  def test_partial_failure_fails_pass_despite_high_overall
    result = RubricLLM::Result.new(
      scores: { a: nil, b: 1.0 },
      details: { a: { error: "boom" } }
    )

    assert_in_delta 1.0, result.overall
    refute_predicate result, :pass?
    assert_equal({ a: "boom" }, result.errors)
  end

  def test_valid_with_no_errors
    result = RubricLLM::Result.new(scores: { a: 0.9 }, details: {})

    assert_predicate result, :valid?
    assert_equal({}, result.errors)
    assert result.pass?(threshold: 0.8)
  end

  def test_errors_ignores_non_hash_details
    result = RubricLLM::Result.new(scores: { a: 0.9 }, details: { a: "some note" })

    assert_equal({}, result.errors)
    assert_predicate result, :valid?
  end
end
