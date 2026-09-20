# frozen_string_literal: true

require "test_helper"

class TestSystemOneAnswer < Minitest::Test
  def test_noul_rejects_nil_nan_and_out_of_range_values
    [nil, Float::NAN, -0.01, 1.01].each do |value|
      assert_raises(RubricLLM::JudgeError) do
        RubricLLM::SystemOne::Answer::Noul.new({ "type" => "noul", "noul" => value })
      end
    end
  end

  def test_choice_preserves_distribution_and_rejects_unknown_choice
    question = RubricLLM::SystemOne::Question.choice("kind", instructions: "Which?", criteria: { a: nil, b: nil })
    raw = {
      "type" => "choice", "choice" => "a", "probabilities" => { "a" => 0.75, "b" => 0.25 }, "confidence" => 0.5
    }
    answer = RubricLLM::SystemOne::Answer::Choice.new(raw, question)

    assert_equal raw, answer.raw
    assert_equal({ "a" => 0.75, "b" => 0.25 }, answer.probabilities)

    invalid = raw.merge("choice" => "c")
    assert_raises(RubricLLM::JudgeError) { RubricLLM::SystemOne::Answer::Choice.new(invalid, question) }
  end

  def test_score_rejects_values_outside_level_range
    question = RubricLLM::SystemOne::Question.score("rating", instructions: "Rate", levels: %w[bad good])
    raw = {
      "type" => "score", "score" => 2.0, "legend" => { "0" => "bad", "1" => "good" },
      "probabilities" => { "0" => 0.0, "1" => 1.0 }, "confidence" => 1.0
    }

    assert_raises(RubricLLM::JudgeError) { RubricLLM::SystemOne::Answer::Score.new(raw, question) }
  end
end
