# frozen_string_literal: true

require_relative "helper"

class ResponseContract < RealClientContract
  def test_empty_capabilities_use_direct_json_without_schema
    stub_response

    assert_in_delta(0.9, judge_call(judge_model: "offline-text").fetch("score"))
    refute @requests.fetch(0).dig("text", "format")
    assert_equal "Judge the answer", @requests.fetch(0)["instructions"]
  end

  def test_empty_capabilities_use_fenced_json_without_schema
    stub_response(content: "```json\n{\"score\":0.75}\n```")

    assert_in_delta(0.75, judge_call(judge_model: "offline-text").fetch("score"))
    refute @requests.fetch(0).dig("text", "format")
  end

  def test_optional_detail_arrays_survive_real_json_text_response
    details = {
      "score" => 0.9, "reasoning" => "offline",
      "claims" => [{ "claim" => "Paris is in France", "supported" => true }],
      "context_scores" => [{ "index" => 0, "relevant" => true }],
      "covered_facts" => [{ "fact" => "Paris", "covered" => true }],
      "discrepancies" => [{ "expected" => "Paris", "actual" => "Paris" }]
    }
    stub_response(content: JSON.generate(details))

    assert_equal details, judge_call
  end

  {
    empty: ["", "Judge response was empty"],
    whitespace: [" \n", "Judge response was empty"],
    malformed: ["not json", "Judge response was not valid JSON"],
    malformed_fence: ["```json\n{bad}\n```", "Judge response code fence was not valid JSON"],
    array: ["[]", "Judge response must be a JSON object"],
    null: ["null", "Judge response must be a JSON object"],
    missing_score: ['{"reasoning":"missing"}', "Judge response missing required score"],
    non_numeric: ['{"score":"no"}', "Judge response score must be numeric"],
    nil_score: ['{"score":null}', "Judge response score must be numeric"],
    non_finite: ['{"score":1e400}', "Judge response score must be between 0.0 and 1.0"],
    negative: ['{"score":-0.1}', "Judge response score must be between 0.0 and 1.0"],
    too_high: ['{"score":1.1}', "Judge response score must be between 0.0 and 1.0"]
  }.each do |name, (content, message)|
    define_method("test_#{name}_response_is_not_retried") do
      RubyLLM.config.max_retries = 2
      stub_response(content:)
      error = assert_raises(RubricLLM::JudgeError) { judge_call(max_retries: 2) }

      assert_includes error.message, message
      assert_equal 1, @requests.size
      assert_equal 1, @connections.size
    end
  end
end
