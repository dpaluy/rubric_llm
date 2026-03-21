# frozen_string_literal: true

require "test_helper"
require "rubric_llm/minitest"

class TestAssertions < Minitest::Test
  include TestSetup
  include RubricLLM::Assertions

  def test_assert_faithful_passes
    stub_judge_response('{"score": 0.9, "claims": [], "reasoning": "supported"}')

    assert_faithful "Paris is the capital.", ["Paris is the capital of France."],
                    question: "What is the capital of France?"
  end

  def test_assert_faithful_fails
    stub_judge_response('{"score": 0.3, "claims": [{"claim": "wrong", "supported": false}], "reasoning": "not supported"}')
    assert_raises(Minitest::Assertion) do
      assert_faithful "Wrong answer", ["Paris is the capital."],
                      question: "What is the capital?"
    end
  end

  def test_assert_relevant_passes
    stub_judge_response('{"score": 0.85, "reasoning": "relevant"}')

    assert_relevant "What is Ruby?", "Ruby is a programming language"
  end

  def test_assert_correct_passes
    stub_judge_response('{"score": 0.95, "reasoning": "matches"}')

    assert_correct "Paris", "Paris", question: "Capital of France?"
  end

  def test_refute_hallucination_passes
    stub_judge_response('{"score": 0.9, "claims": [], "reasoning": "no hallucination"}')

    refute_hallucination "Paris", ["Paris is the capital of France."]
  end
end
