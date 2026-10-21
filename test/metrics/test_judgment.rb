# frozen_string_literal: true

require "test_helper"

class TestJudgmentMetric < Minitest::Test
  include TestSetup

  class ToneMetric < RubricLLM::Metrics::Judgment
    score "How professional is the tone?", %w[Rude Neutral Professional]
  end

  class PolitenessMetric < RubricLLM::Metrics::Judgment
    probability "Is the answer polite?", yes: "Courteous wording", no: "Dismissive wording"
  end

  class StrictToneMetric < ToneMetric; end

  class AnswerOnlyMetric < RubricLLM::Metrics::Judgment
    probability "Is the answer concise?"

    private

    def judgment_input(answer:, **)
      answer
    end
  end

  def test_score_question_is_normalized
    stub_judgment({ metric: fake_score(1) })
    result = metric(ToneMetric).call(question: "q", answer: "a")
    question = RubyLLMStub.fake_judge.last_call[:questions][:metric]

    assert_in_delta 0.5, result[:score]
    assert_equal({ type: :score, instructions: "How professional is the tone?", levels: %w[Rude Neutral Professional] }, question)
    assert_equal :judgment, result[:details][:backend]
  end

  def test_probability_question_scores_probability_of_yes
    stub_judgment({ metric: fake_probability(0.7) })
    result = metric(PolitenessMetric).call(question: "q", answer: "a")
    question = RubyLLMStub.fake_judge.last_call[:questions][:metric]

    assert_in_delta 0.7, result[:score]
    assert_equal({ yes: "Courteous wording", no: "Dismissive wording" }, question[:criteria])
    assert_in_delta 0.7, result[:details][:probability]
  end

  def test_probability_question_omits_empty_criteria
    stub_judgment({ metric: fake_probability(0.7) })
    metric(AnswerOnlyMetric).call(question: "q", answer: "a")

    refute RubyLLMStub.fake_judge.last_call[:questions][:metric].key?(:criteria)
  end

  def test_default_input_includes_present_sample_fields
    stub_judgment({ metric: fake_score(2) })
    metric(ToneMetric).call(question: "q", answer: "a", context: [" c ", ""], ground_truth: nil)

    assert_equal({ question: "q", answer: "a", context: ["c"] }, RubyLLMStub.fake_judge.last_call[:input])
  end

  def test_judgment_input_can_be_overridden
    stub_judgment({ metric: fake_probability(0.4) })
    metric(AnswerOnlyMetric).call(question: "q", answer: "short")

    assert_equal "short", RubyLLMStub.fake_judge.last_call[:input]
  end

  def test_subclasses_inherit_the_question
    stub_judgment({ metric: fake_score(2) })

    assert_in_delta 1.0, metric(StrictToneMetric).call(question: "q", answer: "a")[:score]
  end

  def test_requires_a_judgment_model
    error = assert_raises(RubricLLM::JudgeError) { metric(ToneMetric).call(question: "q", answer: "a") }

    assert_includes error.message, "requires a judgment model"
  end

  def test_requires_a_declared_question
    error = assert_raises(ArgumentError) { metric(Class.new(RubricLLM::Metrics::Judgment)) }

    assert_includes error.message, "must declare a score or probability question"
  end

  def test_malformed_answer_is_a_judge_error
    stub_judgment({ metric: RubyLLMStub::FakeScore.new(score: 1.0, levels: nil, probabilities: {}, confidence: 0.5) })

    assert_raises(RubricLLM::JudgeError) { metric(ToneMetric).call(question: "q", answer: "a") }
  end

  def test_evaluate_records_malformed_answers_instead_of_crashing
    stub_judgment({ metric: Object.new })
    result = RubricLLM.evaluate(question: "q", answer: "a", metrics: [PolitenessMetric])

    assert_nil result.scores[:politeness_metric]
    assert_includes result.details[:politeness_metric][:error], "probability must be numeric"
  end

  def test_evaluate_reports_metric_by_name
    stub_judgment({ metric: fake_score(2) })
    result = RubricLLM.evaluate(question: "q", answer: "a", metrics: [ToneMetric])

    assert_in_delta 1.0, result.scores[:tone_metric]
  end

  def test_score_requires_at_least_two_levels
    error = assert_raises(ArgumentError) do
      Class.new(RubricLLM::Metrics::Judgment) { score "Is it good?", ["Good"] }
    end

    assert_includes error.message, "at least two levels"
  end

  def test_accepts_string_question_types
    stub_judgment({ metric: fake_probability(0.6) })
    klass = Class.new(RubricLLM::Metrics::Judgment) do
      probability "Is it good?"

      def self.question = { "type" => "probability", "instructions" => "Is it good?" }
    end

    assert_in_delta 0.6, metric(klass).call(question: "q", answer: "a")[:score]
  end

  def test_rejects_unsupported_question_types_before_calling_the_model
    stub_judgment
    klass = Class.new(RubricLLM::Metrics::Judgment) do
      probability "Which team?"

      def self.question = { type: :choice, instructions: "Which team?", options: { a: "A" } }
    end

    assert_raises(ArgumentError) { metric(klass).call(question: "q", answer: "a") }
    assert_empty RubyLLMStub.fake_judge.calls
  end

  def test_programming_errors_in_judgment_input_are_not_masked
    stub_judgment({ metric: fake_score(2) })
    klass = Class.new(ToneMetric) do
      private

      def judgment_input(**) = nil.missing_method
    end

    assert_raises(NoMethodError) { metric(klass).call(question: "q", answer: "a") }
  end

  private

  def metric(klass)
    klass.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
  end
end
