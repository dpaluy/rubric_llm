# frozen_string_literal: true

require "test_helper"

class ContextPrecisionBatchJudge
  attr_reader :config, :calls

  def initialize(values:, sentence_limit: 40, fail_on_call: nil)
    @config = RubricLLM::Config.new(judge_backend: :system_one, typesafe_sentence_limit: sentence_limit)
    @values = values
    @fail_on_call = fail_on_call
    @calls = []
  end

  def call(state:, questions:)
    call_number = calls.length + 1
    calls << {
      question: state.fetch(:question), context: state.fetch(:context).dup,
      questions: questions.map(&:to_h), ids: questions.map(&:id)
    }
    raise RubricLLM::JudgeError, "batch #{call_number} failed" if @fail_on_call == call_number

    answers = questions.to_h do |question|
      raw = { "type" => "noul", "noul" => @values.fetch(question.id) }
      [question.id, RubricLLM::SystemOne::Answer::Noul.new(raw)]
    end
    usage = { "input_tokens" => 10 * call_number, "output_tokens" => call_number }
    raw = { "model" => "jev-test", "answers" => answers.transform_values(&:raw), "usage" => usage }
    RubricLLM::SystemOne::Response.new(
      answers:, usage:, model: raw.fetch("model"), latency_ms: 2.5 * call_number, raw:
    )
  end
end

class TestContextPrecisionBatches < Minitest::Test
  QUESTION = "What is Ruby?"
  VALUES = {
    "context_0" => 0.1, "context_1" => 0.3, "context_2" => 0.8,
    "context_3" => 0.9, "context_4" => 1.0
  }.freeze

  def test_batches_contexts_with_global_ids_and_local_indices
    judge = ContextPrecisionBatchJudge.new(values: VALUES, sentence_limit: 2)
    metric(judge).call(question: QUESTION, context: %w[A B C D E])

    batch_sizes = judge.calls.map { |call| call[:questions].length }
    batch_ids = judge.calls.map { |call| call[:ids] }
    instructions = judge.calls.map do |call|
      call[:questions].map { |question| question.fetch(:instructions) }
    end
    questions = judge.calls.map { |call| call[:question] }
    states = judge.calls.map { |call| call[:context] }

    assert_equal [2, 2, 1], batch_sizes
    assert_equal [%w[context_0 context_1], %w[context_2 context_3], ["context_4"]],
                 batch_ids
    assert_equal [
      ["Is `context[0]` useful for answering `question`?", "Is `context[1]` useful for answering `question`?"],
      ["Is `context[0]` useful for answering `question`?", "Is `context[1]` useful for answering `question`?"],
      ["Is `context[0]` useful for answering `question`?"]
    ], instructions
    assert_equal Array.new(3, QUESTION), questions
    assert_equal [%w[A B], %w[C D], ["E"]], states
    assert_equal [
      { type: "noul", instructions: "Is `context[0]` useful for answering `question`?" },
      { type: "noul", instructions: "Is `context[1]` useful for answering `question`?" }
    ], judge.calls.first[:questions]
  end

  def test_aggregates_each_probability_once_and_combines_batch_metadata
    judge = ContextPrecisionBatchJudge.new(values: VALUES, sentence_limit: 2)
    result = metric(judge).call(question: QUESTION, context: %w[A B C D E])
    details = result.fetch(:details)

    assert_in_delta 0.62, result.fetch(:score)
    assert_equal [0.1, 0.3, 0.8, 0.9, 1.0], details.fetch(:probabilities)
    assert_equal({ "input_tokens" => 60, "output_tokens" => 6 }, details.fetch(:usage))
    assert_in_delta 15.0, details.fetch(:latency_ms)
    raw_answers = details.fetch(:raw_answers).transform_values { |answer| answer.fetch("noul") }

    assert_equal VALUES, raw_answers
    assert_equal 3, details.fetch(:raw_responses).length
    assert_equal "jev-test", details.fetch(:model)
    assert_equal :system_one, details.fetch(:backend)
  end

  def test_keeps_single_request_metadata_shape
    judge = ContextPrecisionBatchJudge.new(values: VALUES, sentence_limit: 2)
    result = metric(judge).call(question: QUESTION, context: ["A"])
    details = result.fetch(:details)

    assert_equal :system_one, details.fetch(:backend)
    assert_equal({ "input_tokens" => 10, "output_tokens" => 1 }, details.fetch(:usage))
    assert_in_delta 2.5, details.fetch(:latency_ms)
    assert_equal VALUES.fetch("context_0"), details.fetch(:raw_answers).fetch("context_0").fetch("noul")
    assert_equal "jev-test", details.fetch(:raw_response).fetch("model")
    refute details.key?(:raw_responses)
  end

  def test_empty_context_returns_without_a_request
    judge = ContextPrecisionBatchJudge.new(values: VALUES, sentence_limit: 2)
    result = metric(judge).call(question: QUESTION, context: [" ", "\n"])

    assert_nil result.fetch(:score)
    assert_equal "No context provided", result.fetch(:details).fetch(:error)
    assert_empty judge.calls
  end

  def test_propagates_a_failed_batch_without_returning_a_partial_score
    judge = ContextPrecisionBatchJudge.new(values: VALUES, sentence_limit: 1, fail_on_call: 2)
    error = assert_raises(RubricLLM::JudgeError) do
      metric(judge).call(question: QUESTION, context: %w[A B C])
    end

    assert_equal "batch 2 failed", error.message
    assert_equal 2, judge.calls.length
  end

  private

  def metric(judge)
    RubricLLM::Metrics::ContextPrecision.new(judge:)
  end
end
