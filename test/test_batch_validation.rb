# frozen_string_literal: true

require "test_helper"

class TestBatchValidation < Minitest::Test
  include TestSetup

  def test_evaluate_batch_rejects_non_hash_samples_before_judge_calls
    chat = RubyLLMStub::FakeChat.new
    RubyLLMStub.fake_chat = chat

    error = assert_raises(ArgumentError) do
      RubricLLM.evaluate_batch(
        [{ question: "q1", answer: "a1" }, "not a sample"],
        metrics: [RubricLLM::Metrics::Relevance]
      )
    end

    assert_match "sample at index 1 is not a Hash", error.message
    assert_equal 0, chat.call_count
  end

  def test_evaluate_batch_rejects_samples_missing_required_keys
    [{ question: "q1" }, { "answer" => "a1" }].each_with_index do |sample, index|
      error = assert_raises(ArgumentError) do
        RubricLLM.evaluate_batch([sample], metrics: [RubricLLM::Metrics::Relevance])
      end

      assert_match "sample at index 0", error.message
      assert_match(index.zero? ? ":answer" : ":question", error.message)
    end
  end

  def test_evaluate_batch_rejects_samples_with_nil_required_values_before_judge_calls
    [{ question: nil, answer: "a1" }, { "question" => "q2", "answer" => nil }].each do |sample|
      chat = RubyLLMStub::FakeChat.new
      RubyLLMStub.fake_chat = chat

      error = assert_raises(ArgumentError) do
        RubricLLM.evaluate_batch([sample], metrics: [RubricLLM::Metrics::Relevance])
      end

      assert_match "sample at index 0 has nil", error.message
      assert_equal 0, chat.call_count
    end
  end

  def test_evaluate_batch_accepts_complete_symbol_and_string_keyed_samples
    stub_judge_response('{"score": 0.9, "reasoning": "ok"}')

    report = RubricLLM.evaluate_batch(
      [{ question: "symbol question", answer: "symbol answer" },
       { "question" => "string question", "answer" => "string answer" }],
      metrics: [RubricLLM::Metrics::Relevance]
    )

    assert_equal 2, report.results.size
  end

  def test_evaluate_batch_validates_before_starting_concurrent_work
    chat = RubyLLMStub::FakeChat.new
    RubyLLMStub.fake_chat = chat

    error = assert_raises(ArgumentError) do
      RubricLLM.evaluate_batch(
        [{ question: "q1", answer: "a1" }, { question: "q2" }],
        metrics: [RubricLLM::Metrics::Relevance],
        concurrency: 2
      )
    end

    assert_match "sample at index 1 is missing :answer", error.message
    assert_equal 0, chat.call_count
  end
end
