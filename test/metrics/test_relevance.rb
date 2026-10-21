# frozen_string_literal: true

require "test_helper"

class TestRelevance < Minitest::Test
  include TestSetup

  def test_returns_score
    stub_judge_response('{"score": 0.85, "reasoning": "relevant"}')
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "What is Ruby?", answer: "A programming language")

    assert_in_delta 0.85, result[:score]
  end

  def test_rejects_missing_reasoning
    stub_judge_response('{"score": 0.85}')
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a") }
  end

  def test_raises_for_score_above_one
    stub_judge_response('{"score": 1.5, "reasoning": "over"}')
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: no_retry_config))

    error = assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a") }
    assert_includes error.message, "between 0.0 and 1.0"
  end

  def test_raises_for_score_below_zero
    stub_judge_response('{"score": -0.3, "reasoning": "under"}')
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: no_retry_config))

    error = assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a") }
    assert_includes error.message, "between 0.0 and 1.0"
  end

  def test_judgment_model_scores_relevance_levels
    stub_judgment({ relevance: fake_score(1.5) })
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "Capital?", answer: "Paris")
    question = RubyLLMStub.fake_judge.last_call[:questions][:relevance]

    assert_in_delta 0.75, result[:score]
    assert_equal :judgment, result[:details][:backend]
    assert_in_delta 0.8, result[:details][:confidence]
    assert_equal :score, question[:type]
    assert_equal RubricLLM::Metrics::Relevance::JUDGMENT_LEVELS, question[:levels]
    assert_equal({ question: "Capital?", answer: "Paris" }, RubyLLMStub.fake_judge.last_call[:input])
  end

  def test_judgment_model_rejects_out_of_range_score
    stub_judgment({ relevance: fake_score(3.0) })
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    error = assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a") }
    assert_includes error.message, "between 0.0 and 1.0"
  end

  def test_judgment_model_rejects_missing_answer
    stub_judgment({})
    metric = RubricLLM::Metrics::Relevance.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    error = assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", answer: "a") }
    assert_includes error.message, "missing answer relevance"
  end

  private

  def no_retry_config
    RubricLLM::Config.new(max_retries: 0, retry_base_delay: 0.0)
  end
end
