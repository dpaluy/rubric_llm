# frozen_string_literal: true

require "test_helper"

class TestSystemOneQuestion < Minitest::Test
  def test_choice_wire_shape
    question = RubricLLM::SystemOne::Question.choice(
      :department,
      instructions: "Which team?",
      criteria: { billing: "Payments", technical: nil }
    )

    assert_equal "department", question.id
    assert_equal({ type: "choice", instructions: "Which team?", criteria: { "billing" => "Payments", "technical" => nil } },
                 question.to_h)
  end

  def test_score_wire_shape
    question = RubricLLM::SystemOne::Question.score("quality", instructions: "Rate it", levels: %w[bad okay good])

    assert_equal({ type: "score", instructions: "Rate it", criteria: %w[bad okay good] }, question.to_h)
  end

  def test_noul_wire_shape_with_official_criteria_keys
    question = RubricLLM::SystemOne::Question.noul(
      "urgent",
      instructions: "Is it urgent?",
      criteria: { "true" => "Time-sensitive", "false" => "No urgency" }
    )

    assert_equal({
                   type: "noul", instructions: "Is it urgent?",
                   criteria: { "true" => "Time-sensitive", "false" => "No urgency" }
                 }, question.to_h)
  end

  def test_noul_omits_absent_criteria
    assert_equal({ type: "noul", instructions: "Is it true?" },
                 RubricLLM::SystemOne::Question.noul("truth", instructions: "Is it true?").to_h)
  end

  def test_rejects_invalid_choice_option_counts
    error = assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.choice("empty", instructions: "Choose", criteria: {})
    end

    assert_match(/1\.\.255/, error.message)
    criteria = 256.times.to_h { |index| [index.to_s, nil] }
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.choice("large", instructions: "Choose", criteria:)
    end
  end

  def test_rejects_invalid_score_level_counts
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.score("small", instructions: "Rate", levels: ["only"])
    end
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.score("large", instructions: "Rate", levels: Array.new(11, "level"))
    end
  end

  def test_defensively_copies_and_freezes_mutable_inputs
    id = +"quality"
    instructions = { prompt: [+"Rate it"] }
    levels = [{ label: +"bad" }, { label: +"good" }]
    question = RubricLLM::SystemOne::Question.score(id, instructions:, levels:)

    id.clear
    instructions[:prompt].clear
    levels.pop
    levels.first[:label].clear

    assert_equal "quality", question.id
    assert_equal({ prompt: ["Rate it"] }, question.instructions)
    assert_equal [{ label: "bad" }, { label: "good" }], question.criteria
    assert_raises(FrozenError) { question.instructions[:prompt] << "Changed" }
    assert_raises(FrozenError) { question.criteria.first[:label].clear }
  end

  def test_rejects_wrong_noul_criteria_keys
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.noul("bad", instructions: "True?", criteria: { true_means: "yes", false_means: "no" })
    end
  end

  def test_rejects_empty_id_and_instructions
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.noul(" ", instructions: "True?")
    end
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Question.noul("valid", instructions: "")
    end
  end
end
