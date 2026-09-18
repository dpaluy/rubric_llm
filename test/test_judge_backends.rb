# frozen_string_literal: true

require "test_helper"

class TestJudgeBackends < Minitest::Test
  include TestSetup

  class CustomMetric
    def initialize(judge:)
      @judge = judge
    end

    def call(**)
      response = @judge.call(system_prompt: "custom", user_prompt: "custom")
      { score: Float(response.fetch("score")), details: {} }
    end
  end

  class TypedCustomMetric < CustomMetric
    def call_system_one(**)
      { score: 0.7, details: { backend: :system_one } }
    end
  end

  def test_chat_alias_preserves_existing_judge
    assert_same RubricLLM::Judge, RubricLLM::Judges::Chat
  end

  def test_system_one_runner_delegates_to_client
    client = Object.new
    client.define_singleton_method(:call) { |state:, questions:| [state, questions] }
    config = RubricLLM::Config.new
    runner = RubricLLM::Judges::SystemOne.new(config:, client:)

    assert_equal [{ answer: "a" }, [:question]], runner.call(state: { answer: "a" }, questions: [:question])
    assert_same config, runner.config
  end

  def test_custom_metric_is_rejected_clearly_by_system_one_backend
    config = RubricLLM::Config.new(judge_backend: :system_one, typesafe_api_key: "test-key")

    error = assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::Evaluator.new(config:, metrics: [CustomMetric]).call(question: "q", answer: "a")
    end
    assert_match(/implement #call_system_one/, error.message)
  end

  def test_custom_metric_with_system_one_strategy_is_supported
    config = RubricLLM::Config.new(judge_backend: :system_one, typesafe_api_key: "test-key")
    result = RubricLLM::Evaluator.new(config:, metrics: [TypedCustomMetric]).call(question: "q", answer: "a")

    assert_in_delta 0.7, result.scores[:typed_custom_metric]
    assert_equal :system_one, result.details[:typed_custom_metric][:backend]
  end

  def test_custom_metric_remains_chat_compatible_under_cascade_until_cascade_stage
    stub_judge_response('{"score": 0.6}')
    config = RubricLLM::Config.new(judge_backend: :cascade, typesafe_api_key: "test-key")
    result = RubricLLM::Evaluator.new(config:, metrics: [CustomMetric]).call(question: "q", answer: "a")

    assert_in_delta 0.6, result.scores[:custom_metric]
  end
end
