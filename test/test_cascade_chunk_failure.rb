# frozen_string_literal: true

require "test_helper"

class TestCascadeChunkFailure < Minitest::Test
  FakeNoul = Struct.new(:probability)

  class ChunkRunner
    def initialize(*outcomes)
      @outcomes = outcomes
    end

    def call(**)
      outcome = @outcomes.shift
      raise outcome if outcome.is_a?(Exception)

      outcome
    end
  end

  class ChatRunner
    attr_reader :last_usage

    def call(**)
      @last_usage = { input_tokens: 10, output_tokens: 2 }
      { "score" => 0.9, "claims" => [], "reasoning" => "fallback" }
    end
  end

  def test_later_chunk_failure_marks_total_usage_unknown_and_preserves_completed_evidence
    response = RubricLLM::SystemOne::Response.new(
      answers: { "sentence_0" => FakeNoul.new(0.9) },
      usage: { "input_tokens" => 3, "output_tokens" => 1 },
      model: "jev-1.2.3",
      latency_ms: 4.0,
      raw: { "answers" => { "sentence_0" => { "type" => "noul", "noul" => 0.9 } } }
    )
    system_one = ChunkRunner.new(response, RubricLLM::JudgeError.new("second chunk failed"))
    config = RubricLLM::Config.new(
      typesafe_api_key: "secret", judge_backend: :cascade, typesafe_sentence_limit: 1
    )
    cascade = RubricLLM::Judges::Cascade.new(config:, system_one:, chat: ChatRunner.new)
    metric = RubricLLM::Metrics::Faithfulness.new(judge: cascade)

    result = cascade.evaluate_metric(
      metric, question: "q", answer: "First sentence. Second sentence.", context: ["context"]
    )
    system_one_details = result[:details][:system_one]

    assert_in_delta 0.9, result[:score]
    assert result[:details][:escalated]
    assert_equal 1, system_one_details[:raw_responses].length
    assert_equal({ "input_tokens" => 3, "output_tokens" => 1 }, system_one_details[:completed_usage])
    assert_nil system_one_details[:usage]

    report_result = RubricLLM::Result.new(
      scores: { faithfulness: result[:score] }, details: { faithfulness: result[:details] }
    )
    report = RubricLLM::Report.new(results: [report_result])

    assert_nil report.total_usage
    refute_predicate report, :usage_complete?
    refute JSON.parse(report.to_json)["usage_complete"]
  end
end
