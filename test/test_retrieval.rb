# frozen_string_literal: true

require "test_helper"

class TestRetrievalResult < Minitest::Test
  def setup
    @result = RubricLLM.evaluate_retrieval(
      retrieved: %w[doc1 doc2 doc3],
      relevant: %w[doc1 doc3]
    )
  end

  def test_precision_at_k
    assert_in_delta 0.667, @result.precision_at_k(3), 0.001
  end

  def test_recall_at_k
    assert_in_delta 1.0, @result.recall_at_k(3)
  end

  def test_mrr
    assert_in_delta 1.0, @result.mrr
  end

  def test_ndcg
    assert_operator @result.ndcg, :>, 0.0
    assert_operator @result.ndcg, :<=, 1.0
  end

  def test_hit_rate
    assert_in_delta 1.0, @result.hit_rate
  end

  def test_no_relevant_docs
    result = RubricLLM.evaluate_retrieval(retrieved: ["doc1"], relevant: [])

    assert_in_delta 0.0, result.precision_at_k(1)
    assert_in_delta 0.0, result.recall_at_k(1)
    assert_in_delta 0.0, result.mrr
  end

  def test_no_hits
    result = RubricLLM.evaluate_retrieval(retrieved: ["doc1"], relevant: ["doc2"])

    assert_in_delta 0.0, result.precision_at_k(1)
    assert_in_delta 0.0, result.mrr
    assert_in_delta 0.0, result.hit_rate
  end

  def test_to_h
    hash = @result.to_h

    assert hash.key?(:precision_at_k)
    assert hash.key?(:recall_at_k)
    assert hash.key?(:mrr)
    assert hash.key?(:ndcg)
    assert hash.key?(:hit_rate)
  end
end
