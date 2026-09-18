# frozen_string_literal: true

require "test_helper"

class FakeSystemOneMetricJudge
  attr_reader :config, :calls

  def initialize(values: {}, sentence_limit: 40)
    @config = RubricLLM::Config.new(judge_backend: :system_one, typesafe_api_key: "test-key", typesafe_sentence_limit: sentence_limit)
    @values = values
    @calls = []
  end

  def call(state:, questions:)
    calls << { state:, questions: questions.map(&:to_h), ids: questions.map(&:id) }
    answers = questions.to_h do |question|
      raw = answer_for(question)
      answer = question.type == :noul ? RubricLLM::SystemOne::Answer::Noul.new(raw) : RubricLLM::SystemOne::Answer::Score.new(raw, question)
      [question.id, answer]
    end
    raw = { "model" => "jev-1.13.0", "answers" => answers.transform_values(&:raw),
            "usage" => { "input_tokens" => 2, "output_tokens" => 1 } }
    RubricLLM::SystemOne::Response.new(
      answers:, usage: raw["usage"], model: raw["model"], latency_ms: 3.5, raw:
    )
  end

  private

  def answer_for(question)
    value = @values.fetch(question.id, question.type == :score ? 2.0 : 0.5)
    return { "type" => "noul", "noul" => value } if question.type == :noul

    probabilities = Array.new(question.criteria.length, 0.0)
    probabilities[value.to_i] = 1.0
    {
      "type" => "score", "score" => value,
      "legend" => question.criteria.each_with_index.to_h { |level, index| [index.to_s, level] },
      "probabilities" => probabilities.each_with_index.to_h { |probability, index| [index.to_s, probability] },
      "confidence" => 0.91
    }
  end
end

class TestSystemOneMetrics < Minitest::Test
  SAMPLE = { question: "What is Ruby?", answer: "Ruby is a language. It is red!", context: ["Ruby is a language."],
             ground_truth: "Ruby is a language. Ruby was created in Japan." }.freeze

  def test_text_sentences_is_deterministic
    assert_equal ["One.", "Two!", "Three?", "Four"], RubricLLM::Text.sentences(" One.\nTwo! Three? Four ")
    assert_empty RubricLLM::Text.sentences(" \n ")
  end

  def test_faithfulness_question_snapshot_and_mean_min_aggregation
    judge = FakeSystemOneMetricJudge.new(values: { "sentence_0" => 0.8, "sentence_1" => 0.2 })
    mean = RubricLLM::Metrics::Faithfulness.new(judge:).call(**SAMPLE)
    minimum = RubricLLM::Metrics::Faithfulness.new(judge:, aggregate: :min).call(**SAMPLE)

    first_instruction = "Is `sentences[0]` fully supported by the information in `context`? " \
                        "Yes only if every factual element appears in or follows directly from the context."
    second_instruction = "Is `sentences[1]` fully supported by the information in `context`? " \
                         "Yes only if every factual element appears in or follows directly from the context."
    expected = [
      { type: "noul", instructions: first_instruction },
      { type: "noul", instructions: second_instruction }
    ]

    assert_equal expected, judge.calls.first[:questions]
    assert_in_delta 0.5, mean[:score]
    assert_in_delta 0.2, minimum[:score]
    assert_equal({ mean: 0.5, min: 0.2, aggregate: :mean }, mean[:details].slice(:mean, :min, :aggregate))
  end

  def test_relevance_question_snapshot_and_aggregation
    judge = FakeSystemOneMetricJudge.new(values: { "relevance" => 3.0 })
    result = RubricLLM::Metrics::Relevance.new(judge:).call(**SAMPLE)

    assert_equal [{ type: "score", instructions: "How well does `answer` answer `question`?", criteria: [
      "The answer ignores the question.",
      "The answer touches the topic but does not answer the question.",
      "The answer partially answers the question.",
      "The answer answers the question with minor gaps or padding.",
      "The answer directly and completely answers the question."
    ] }], judge.calls.first[:questions]
    assert_in_delta 0.75, result[:score]
    assert_in_delta(0.91, result[:details][:confidence])
  end

  def test_correctness_question_snapshot_and_aggregation
    judge = FakeSystemOneMetricJudge.new(values: { "correctness" => 3.0, "contradiction" => 0.25 })
    result = RubricLLM::Metrics::Correctness.new(judge:).call(**SAMPLE)

    assert_equal [
      { type: "score", instructions: "How closely does `answer` match `ground_truth` for `question`?", criteria: [
        "The answer contradicts the ground truth.",
        "The answer is mostly wrong compared with the ground truth.",
        "The answer partially matches the ground truth.",
        "The answer matches the ground truth with minor omissions.",
        "The answer is semantically equivalent to the ground truth."
      ] },
      { type: "noul", instructions: "Does `answer` contradict `ground_truth` on any specific fact?" }
    ], judge.calls.first[:questions]
    assert_in_delta 0.75, result[:score]
    assert_in_delta 0.25, result[:details][:contradiction_probability]
  end

  def test_factual_accuracy_question_snapshot_and_aggregation
    judge = FakeSystemOneMetricJudge.new(values: { "sentence_0" => 0.1, "sentence_1" => 0.3 })
    result = RubricLLM::Metrics::FactualAccuracy.new(judge:).call(**SAMPLE)

    assert_equal [
      { type: "noul", instructions: "Does `sentences[0]` state something that conflicts with `ground_truth`?" },
      { type: "noul", instructions: "Does `sentences[1]` state something that conflicts with `ground_truth`?" }
    ], judge.calls.first[:questions]
    assert_in_delta 0.8, result[:score]
  end

  def test_context_precision_question_snapshot_and_aggregation
    sample = SAMPLE.merge(context: %w[Useful Noise])
    judge = FakeSystemOneMetricJudge.new(values: { "context_0" => 0.9, "context_1" => 0.1 })
    result = RubricLLM::Metrics::ContextPrecision.new(judge:).call(**sample)

    assert_equal [
      { type: "noul", instructions: "Is `context[0]` useful for answering `question`?" },
      { type: "noul", instructions: "Is `context[1]` useful for answering `question`?" }
    ], judge.calls.first[:questions]
    assert_in_delta 0.5, result[:score]
  end

  def test_context_recall_question_snapshot_and_aggregation
    judge = FakeSystemOneMetricJudge.new(values: { "sentence_0" => 0.7, "sentence_1" => 0.9 })
    result = RubricLLM::Metrics::ContextRecall.new(judge:).call(**SAMPLE)

    assert_equal [
      { type: "noul", instructions: "Is the information in `sentences[0]` present in `context`?" },
      { type: "noul", instructions: "Is the information in `sentences[1]` present in `context`?" }
    ], judge.calls.first[:questions]
    assert_in_delta 0.8, result[:score]
  end

  def test_sentence_metrics_chunk_every_sentence_and_retain_metadata
    sample = SAMPLE.merge(answer: "One. Two. Three. Four. Five.")
    judge = FakeSystemOneMetricJudge.new(sentence_limit: 2)
    result = RubricLLM::Metrics::Faithfulness.new(judge:).call(**sample)

    assert_equal([2, 2, 1], judge.calls.map { |call| call[:questions].length })
    assert_equal(%w[sentence_0 sentence_1 sentence_2 sentence_3 sentence_4], judge.calls.flat_map { |call| call[:ids] })
    assert_equal 5, result[:details][:raw_answers].length
    assert_equal 3, result[:details][:raw_responses].length
    assert_equal({ "input_tokens" => 6, "output_tokens" => 3 }, result[:details][:usage])
  end

  def test_missing_and_empty_inputs_return_nil_without_calling_system_one
    judge = FakeSystemOneMetricJudge.new
    cases = [
      RubricLLM::Metrics::Faithfulness.new(judge:).call(**SAMPLE, context: []),
      RubricLLM::Metrics::Faithfulness.new(judge:).call(**SAMPLE, answer: ""),
      RubricLLM::Metrics::Correctness.new(judge:).call(**SAMPLE, ground_truth: nil),
      RubricLLM::Metrics::FactualAccuracy.new(judge:).call(**SAMPLE, ground_truth: nil),
      RubricLLM::Metrics::ContextPrecision.new(judge:).call(**SAMPLE, context: []),
      RubricLLM::Metrics::ContextRecall.new(judge:).call(**SAMPLE, ground_truth: "")
    ]

    assert(cases.all? { |result| result[:score].nil? })
    assert(cases.all? { |result| result[:details][:error] })
    assert_empty judge.calls
  end

  def test_system_one_details_retain_raw_answer_and_response
    judge = FakeSystemOneMetricJudge.new(values: { "relevance" => 4.0 })
    result = RubricLLM::Metrics::Relevance.new(judge:).call(**SAMPLE)

    assert_equal :system_one, result[:details][:backend]
    assert_equal "score", result[:details][:raw_answers]["relevance"]["type"]
    assert_equal "jev-1.13.0", result[:details][:raw_response]["model"]
  end
end
