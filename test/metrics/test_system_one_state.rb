# frozen_string_literal: true

require "test_helper"

class RecordingSystemOneJudge
  attr_reader :config, :calls

  def initialize(sentence_limit: 40, custom_prompt: nil, &responder)
    @config = RubricLLM::Config.new(
      judge_backend: :system_one, typesafe_api_key: "offline", typesafe_sentence_limit: sentence_limit, custom_prompt:
    )
    @responder = responder
    @calls = []
  end

  def call(state:, questions:)
    calls << { state:, questions: questions.map(&:to_h) }
    answers = questions.to_h do |question|
      probability = @responder ? @responder.call(state) : 0.9
      raw = { "type" => "noul", "noul" => probability }
      [question.id, RubricLLM::SystemOne::Answer::Noul.new(raw)]
    end
    raw = { "model" => "offline", "answers" => answers.transform_values(&:raw),
            "usage" => { "input_tokens" => 1, "output_tokens" => 1 } }
    RubricLLM::SystemOne::Response.new(answers:, usage: raw["usage"], model: raw["model"], latency_ms: 0.0, raw:)
  end
end

class TestSystemOneState < Minitest::Test
  def test_custom_prompt_is_added_without_mutating_original_instructions
    client = RecordingSystemOneJudge.new(custom_prompt: "Treat tentative claims as unsupported.")
    judge = RubricLLM::Judges::SystemOne.new(config: client.config, client:)
    string_question = RubricLLM::SystemOne::Question.noul("string", instructions: "Base instruction")
    structured_instructions = { "task" => ["Keep", "this structure"] }
    structured_question = RubricLLM::SystemOne::Question.noul("structured", instructions: structured_instructions)

    RubricLLM::Metrics::Base.new(judge:).system_one_eval(state: "sample", questions: [string_question, structured_question])

    expected_suffix = "Additional instructions:\nTreat tentative claims as unsupported."

    assert_equal "Base instruction\n\n#{expected_suffix}", client.calls.first[:questions][0][:instructions]
    assert_equal [structured_instructions, { "additional_instructions" => "Treat tentative claims as unsupported." }],
                 client.calls.first[:questions][1][:instructions]
    assert_equal "Base instruction", string_question.instructions
    assert_equal structured_instructions, structured_question.instructions
  end

  def test_custom_prompt_applies_to_direct_typed_judge_calls
    client = RecordingSystemOneJudge.new(custom_prompt: "Use the stated policy.")
    judge = RubricLLM::Judges::SystemOne.new(config: client.config, client:)
    question = RubricLLM::SystemOne::Question.noul("q", instructions: "Is it supported?")

    judge.call(state: "sample", questions: [question])

    assert_equal "Is it supported?\n\nAdditional instructions:\nUse the stated policy.",
                 client.calls.first[:questions].first[:instructions]
    assert_equal "Is it supported?", question.instructions
  end

  def test_faithfulness_keeps_question_and_complete_answer_in_every_batch
    answer = "Alice designed the bridge. She supervised construction. It opened in 2020."
    question = "Who designed and supervised the bridge?"
    judge = RecordingSystemOneJudge.new(sentence_limit: 1)

    RubricLLM::Metrics::Faithfulness.new(judge:).call(question:, answer:, context: ["Alice built the bridge."])

    assert_equal 3, judge.calls.length
    assert(judge.calls.all? { |call| call[:state][:question] == question })
    assert(judge.calls.all? { |call| call[:state][:answer] == answer })
    assert_equal ["She supervised construction."], judge.calls[1][:state][:sentences]
  end

  def test_faithfulness_uses_question_to_interpret_a_short_answer
    judge = RecordingSystemOneJudge.new { |state| state[:question] == "Is the sky blue?" ? 0.95 : 0.05 }
    metric = RubricLLM::Metrics::Faithfulness.new(judge:)
    sample = { answer: "Yes.", context: ["The sky is blue, not green."] }

    supported = metric.call(**sample, question: "Is the sky blue?")
    unsupported = metric.call(**sample, question: "Is the sky green?")

    assert_in_delta 0.95, supported[:score]
    assert_in_delta 0.05, unsupported[:score]
  end

  def test_context_recall_keeps_complete_ground_truth_in_every_batch
    ground_truth = "Alice designed the bridge. She supervised construction. It opened in 2020."
    judge = RecordingSystemOneJudge.new(sentence_limit: 1)

    RubricLLM::Metrics::ContextRecall.new(judge:).call(context: ["Alice built the bridge."], ground_truth:)

    assert_equal 3, judge.calls.length
    assert(judge.calls.all? { |call| call[:state][:ground_truth] == ground_truth })
    assert_equal ["She supervised construction."], judge.calls[1][:state][:sentences]
  end
end
