# frozen_string_literal: true

require "test_helper"

class TestJudgeJudgment < Minitest::Test
  include TestSetup

  QUESTIONS = { quality: { type: :score, instructions: "How good is it?", levels: %w[bad ok good] } }.freeze

  def test_judgment_is_false_for_chat_models
    refute_predicate judge, :judgment?
  end

  def test_judgment_is_true_for_judgment_models
    stub_judgment

    assert_predicate judge, :judgment?
  end

  def test_judgment_wraps_model_lookup_errors
    RubyLLMStub.models.error = RuntimeError.new("Unknown model: jev-latest")

    error = assert_raises(RubricLLM::JudgeError) { judge.judgment? }
    assert_includes error.message, "Unknown model: jev-latest"
  end

  def test_models_missing_from_the_registry_use_chat
    RubyLLMStub.models.error = RubyLLMReal::ModelNotFoundError.new("Unknown model: my-local-llama")
    stub_judge_response('{"score": 0.9, "reasoning": "local"}')

    instance = judge(judge_model: "my-local-llama", judge_provider: :ollama)

    refute_predicate instance, :judgment?
    assert_in_delta 0.9, instance.call(system_prompt: "s", user_prompt: "u")["score"]
  end

  def test_judgment_follows_config_changes
    config = RubricLLM::Config.new(judge_model: "gpt-4o", judge_provider: :openai)
    instance = RubricLLM::Judge.new(config:)

    refute_predicate instance, :judgment?

    stub_judgment
    config.judge_model = "jev-latest"

    assert_predicate instance, :judgment?
  end

  def test_judge_sends_input_questions_model_and_provider
    stub_judgment({ quality: fake_score(2) })

    result = judge(judge_model: "jev-latest", judge_provider: :typesafe).judge({ answer: "a" }, questions: QUESTIONS)

    call = RubyLLMStub.fake_judge.last_call

    assert_in_delta 2.0, result[:quality].score
    assert_equal({ answer: "a" }, call[:input])
    assert_equal QUESTIONS, call[:questions]
    assert_equal "jev-latest", call[:model]
    assert_equal :typesafe, call[:provider]
  end

  def test_judge_appends_custom_prompt_to_question_instructions
    stub_judgment({ quality: fake_score(2) })

    judge(custom_prompt: "Be strict.").judge("input", questions: QUESTIONS)

    instructions = RubyLLMStub.fake_judge.last_call[:questions][:quality][:instructions]

    assert_equal "How good is it?\n\nAdditional instructions:\nBe strict.", instructions
  end

  def test_judge_retries_transient_errors
    stub_judgment({ quality: fake_score(2) }, fail_times: 2, error_class: RubyLLMReal::RateLimitError)

    judge(max_retries: 2).judge("input", questions: QUESTIONS)

    assert_equal 3, RubyLLMStub.fake_judge.calls.size
  end

  def test_judge_does_not_retry_permanent_errors
    stub_judgment({}, fail_times: 1, error_class: RubyLLMReal::UnauthorizedError)

    error = assert_raises(RubricLLM::JudgeError) { judge(max_retries: 2).judge("input", questions: QUESTIONS) }

    assert_includes error.message, "Judge call failed"
    assert_equal 1, RubyLLMStub.fake_judge.calls.size
  end

  def test_judge_rejects_chat_models
    error = assert_raises(RubricLLM::JudgeError) { judge.judge("input", questions: QUESTIONS) }

    assert_includes error.message, "does not answer judgments"
  end

  def test_call_rejects_judgment_models
    stub_judgment

    error = assert_raises(RubricLLM::JudgeError) { judge.call(system_prompt: "s", user_prompt: "u") }

    assert_includes error.message, "requires a chat model"
  end

  def test_judge_keeps_structured_instructions_with_custom_prompt
    stub_judgment({ quality: fake_score(2) })
    questions = { quality: { type: :score, instructions: { rubric: "Grade it" }, levels: %w[bad ok good] } }

    judge(custom_prompt: "Be strict.").judge("input", questions:)

    assert_equal({ instructions: { rubric: "Grade it" }, additional_instructions: "Be strict." },
                 RubyLLMStub.fake_judge.last_call[:questions][:quality][:instructions])
  end

  def test_judge_keeps_string_keyed_instructions_with_custom_prompt
    stub_judgment({ quality: fake_score(2) })
    questions = { quality: { "type" => :score, "instructions" => "How good is it?", "levels" => %w[bad ok good] } }

    judge(custom_prompt: "Be strict.").judge("input", questions:)

    assert_equal "How good is it?\n\nAdditional instructions:\nBe strict.",
                 RubyLLMStub.fake_judge.last_call[:questions][:quality][:instructions]
  end

  def test_judge_uses_custom_prompt_when_question_has_no_instructions
    stub_judgment({ quality: fake_score(2) })

    judge(custom_prompt: "Be strict.").judge("input", questions: { quality: { type: :score, levels: %w[bad good] } })

    assert_equal "Be strict.", RubyLLMStub.fake_judge.last_call[:questions][:quality][:instructions]
  end

  private

  def judge(**)
    RubricLLM::Judge.new(config: RubricLLM::Config.new(retry_base_delay: 0, **))
  end
end
