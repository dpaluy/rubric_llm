# frozen_string_literal: true

require "test_helper"

class TestContextPrecision < Minitest::Test
  include TestSetup

  def test_returns_score
    stub_judge_response('{"score": 0.8, "context_scores": [{"index": 1, "relevant": true, "reason": "ok"}], "reasoning": "good"}')
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "What is Ruby?", context: ["Ruby is a language"])

    assert_in_delta 1.0, result[:score]
  end

  def test_score_counts_relevant_chunks
    stub_judge_response('{"score": 0.9, "context_scores": ' \
                        '[{"index": 1, "relevant": true, "reason": "useful"}, ' \
                        '{"index": 2, "relevant": false, "reason": "unrelated"}], "reasoning": "one of two"}')
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    result = metric.call(question: "q", context: %w[useful unrelated])

    assert_in_delta 0.5, result[:score]
  end

  def test_rejects_missing_chunk
    stub_judge_response('{"score": 1.0, "context_scores": [{"index": 1, "relevant": true, "reason": "yes"}], "reasoning": "ok"}')
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", context: %w[a b]) }
  end

  def test_rejects_decimal_context_indices
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    [1.0, 1.5].each do |index|
      stub_judge_response(JSON.generate(score: 1.0, reasoning: "relevant",
                                        context_scores: [{ index:, relevant: true, reason: "useful" }]))

      error = assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", context: ["a"]) }
      assert_includes error.message, "invalid context indices"
    end
  end

  def test_nil_without_context
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "q")

    assert_nil result[:score]
    assert_equal "No context provided", result[:details][:error]
  end

  def test_judgment_model_asks_one_probability_per_context
    stub_judgment({ "context_1" => fake_probability(0.9), "context_2" => fake_probability(0.2), "context_3" => fake_probability(0.5) })
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))
    result = metric.call(question: "Capital?", context: %w[Paris Bananas France])
    call = RubyLLMStub.fake_judge.last_call

    assert_in_delta 2.0 / 3, result[:score]
    assert_equal %w[context_1 context_2 context_3], call[:questions].keys.map(&:to_s)
    assert_equal([:probability] * 3, call[:questions].values.map { |question| question[:type] })
    assert_equal({ "context_1" => "Paris", "context_2" => "Bananas", "context_3" => "France" },
                 call[:input][:contexts].transform_keys(&:to_s))
    assert_equal({ "index" => 2, "relevant" => false, "probability" => 0.2 }, result[:details][:context_scores][1])
  end

  def test_judgment_model_uses_configured_threshold
    stub_judgment({ "context_1" => fake_probability(0.3), "context_2" => fake_probability(0.1) })
    config = RubricLLM::Config.new(judgment_threshold: 0.25)
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config:))
    result = metric.call(question: "q", context: %w[a b])

    assert_in_delta 0.5, result[:score]
    assert_in_delta 0.25, result[:details][:threshold]
  end

  def test_judgment_model_rejects_invalid_probability
    stub_judgment({ "context_1" => fake_probability(1.5) })
    metric = RubricLLM::Metrics::ContextPrecision.new(judge: RubricLLM::Judge.new(config: RubricLLM.config))

    assert_raises(RubricLLM::JudgeError) { metric.call(question: "q", context: ["c"]) }
  end
end
