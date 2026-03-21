# frozen_string_literal: true

require "test_helper"

class TestEvaluator < Minitest::Test
  include TestSetup

  def test_evaluate_returns_result
    stub_judge_response('{"score": 0.9, "reasoning": "good"}')
    result = RubricLLM.evaluate(
      question: "What is Ruby?",
      answer: "A programming language",
      context: ["Ruby is a programming language"],
      ground_truth: "A programming language"
    )

    assert_instance_of RubricLLM::Result, result
    assert result.scores.key?(:faithfulness)
    assert result.scores.key?(:relevance)
    assert result.scores.key?(:correctness)
  end

  def test_evaluate_with_selected_metrics
    stub_judge_response('{"score": 0.85, "reasoning": "ok"}')
    result = RubricLLM.evaluate(
      question: "test",
      answer: "test",
      metrics: [RubricLLM::Metrics::Relevance]
    )

    assert result.scores.key?(:relevance)
    refute result.scores.key?(:faithfulness)
  end

  def test_evaluate_default_metrics_include_factual_accuracy
    stub_judge_response('{"score": 0.9, "reasoning": "good"}')
    result = RubricLLM.evaluate(
      question: "What is Ruby?",
      answer: "A programming language",
      context: ["Ruby is a programming language"],
      ground_truth: "Ruby is a programming language"
    )

    assert result.scores.key?(:factual_accuracy)
  end

  def test_evaluate_handles_judge_failure
    stub_judge_response("completely broken response")
    result = RubricLLM.evaluate(
      question: "test",
      answer: "test",
      metrics: [RubricLLM::Metrics::Relevance]
    )

    assert_nil result.scores[:relevance]
  end

  def test_evaluate_with_custom_prompt
    chat = RubyLLMStub::FakeChat.new(response_content: '{"score": 0.8, "reasoning": "ok"}')
    RubyLLMStub.fake_chat = chat

    RubricLLM.evaluate(
      question: "test",
      answer: "test",
      metrics: [RubricLLM::Metrics::Relevance],
      custom_prompt: "Be strict about medical accuracy."
    )

    assert_includes chat.last_system_prompt, "Additional instructions:"
    assert_includes chat.last_system_prompt, "Be strict about medical accuracy."
  end

  def test_evaluate_custom_prompt_does_not_mutate_global_config
    stub_judge_response('{"score": 0.8, "reasoning": "ok"}')

    RubricLLM.evaluate(
      question: "test",
      answer: "test",
      metrics: [RubricLLM::Metrics::Relevance],
      custom_prompt: "Be strict."
    )

    assert_nil RubricLLM.config.custom_prompt
  end

  def test_evaluate_batch_sequential
    stub_judge_response('{"score": 0.9, "reasoning": "good"}')
    dataset = [
      { question: "q1", answer: "a1", context: ["c1"], ground_truth: "gt1" },
      { question: "q2", answer: "a2", context: ["c2"], ground_truth: "gt2" }
    ]

    report = RubricLLM.evaluate_batch(dataset, metrics: [RubricLLM::Metrics::Relevance])

    assert_equal 2, report.results.size
    assert_in_delta 0.9, report.results.first.scores[:relevance]
  end

  def test_evaluate_batch_concurrent
    stub_judge_response('{"score": 0.85, "reasoning": "ok"}')
    dataset = [
      { question: "q1", answer: "a1" },
      { question: "q2", answer: "a2" },
      { question: "q3", answer: "a3" }
    ]

    report = RubricLLM.evaluate_batch(dataset, metrics: [RubricLLM::Metrics::Relevance], concurrency: 2)

    assert_equal 3, report.results.size
    report.results.each do |result|
      assert_in_delta 0.85, result.scores[:relevance]
    end
  end

  def test_evaluate_batch_preserves_order_with_concurrency
    stub_judge_response('{"score": 0.9, "reasoning": "ok"}')
    dataset = (1..5).map { |i| { question: "q#{i}", answer: "a#{i}" } }

    report = RubricLLM.evaluate_batch(dataset, metrics: [RubricLLM::Metrics::Relevance], concurrency: 3)

    assert_equal 5, report.results.size
    report.results.each_with_index do |result, i|
      assert_equal "q#{i + 1}", result.sample[:question]
    end
  end
end
