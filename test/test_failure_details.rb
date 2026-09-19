# frozen_string_literal: true

require "test_helper"
require "rubric_llm/failure_details"

class TestFailureDetails < Minitest::Test
  def test_missing_details_remain_empty
    [nil, {}, "unexpected"].each { |details| assert_empty RubricLLM::FailureDetails.format(details) }
  end

  def test_chat_claims_keep_precedence_over_reasoning
    details = { claims: [{ "claim" => "unsupported", "supported" => false }], reasoning: "other reason" }

    assert_equal ' Claims not supported: ["unsupported"]', RubricLLM::FailureDetails.format(details)
    assert_equal " reason", RubricLLM::FailureDetails.format(reasoning: "reason")
  end

  def test_probabilities_are_bounded_and_payloads_are_excluded
    details = { probabilities: Array.new(100, 0.1), raw_answers: { secret: "PRIVATE" },
                raw_response: { secret: "PRIVATE" }, context: "PRIVATE", escalation_reason: "x" * 1_000 }
    message = RubricLLM::FailureDetails.format(details)

    assert_includes message, "(+94 more)"
    assert_operator message.length, :<, 400
    refute_includes message, "PRIVATE"
    refute_includes message, "x" * 241
  end

  def test_nested_request_errors_are_reported_without_raw_response_dump
    details = { escalated: true, system_one: { backend: :system_one, error: "HTTP 413", raw_responses: ["PRIVATE"] } }
    message = RubricLLM::FailureDetails.format(details)

    assert_includes message, "System One attempt: backend=system_one, error=HTTP 413"
    refute_includes message, "PRIVATE"
  end
end
