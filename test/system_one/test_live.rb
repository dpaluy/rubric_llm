# frozen_string_literal: true

require "test_helper"

class TestSystemOneLive < Minitest::Test
  def setup
    super
    skip "set RUBRIC_LIVE_TESTS=1 and TYPESAFE_API_KEY to run" unless live_enabled?

    config = RubricLLM::Config.new(typesafe_api_key: ENV.fetch("TYPESAFE_API_KEY"), typesafe_timeout: 30)
    @client = RubricLLM::SystemOne::Client.new(config:)
  end

  def test_live_noul_primitive
    question = RubricLLM::SystemOne::Question.noul("true", instructions: "Is `statement` true?")
    response = @client.call(state: { statement: "Paris is in France." }, questions: [question])

    assert_instance_of RubricLLM::SystemOne::Answer::Noul, response.answers.fetch("true")
  end

  def test_live_choice_primitive
    question = RubricLLM::SystemOne::Question.choice(
      "category", instructions: "Which category describes `message`?", criteria: { greeting: nil, complaint: nil }
    )
    response = @client.call(state: { message: "Hello there" }, questions: [question])

    assert_instance_of RubricLLM::SystemOne::Answer::Choice, response.answers.fetch("category")
  end

  def test_live_score_primitive
    question = RubricLLM::SystemOne::Question.score(
      "sentiment", instructions: "How positive is `message`?", levels: %w[Negative Neutral Positive]
    )
    response = @client.call(state: { message: "This is wonderful." }, questions: [question])

    assert_instance_of RubricLLM::SystemOne::Answer::Score, response.answers.fetch("sentiment")
  end

  private

  def live_enabled?
    ENV["RUBRIC_LIVE_TESTS"] == "1" && !ENV.fetch("TYPESAFE_API_KEY", "").strip.empty?
  end
end
