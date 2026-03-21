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
  end
end
