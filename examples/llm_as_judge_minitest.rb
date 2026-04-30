# frozen_string_literal: true

# Use RubricLLM's Minitest assertions as a live LLM-as-Judge smoke test.
#
# Run from the project root after configuring RubyLLM provider credentials:
#
#   OPENAI_API_KEY=... bundle exec ruby examples/llm_as_judge_minitest.rb

require "minitest/autorun"
require "rubric_llm/minitest"

warn "OPENAI_API_KEY is not set. If RubyLLM is not configured another way, judge calls will fail." unless ENV.key?("OPENAI_API_KEY")

JUDGE_MODEL = "gpt-4.1"
EVALUATED_SYSTEM = "acme-rag-v1 (pre-generated answer under test)"

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

RubricLLM.configure do |config|
  config.judge_model = JUDGE_MODEL
  config.judge_provider = :openai
end

puts "Judge model: #{JUDGE_MODEL}"
puts "Evaluated system: #{EVALUATED_SYSTEM}"

class TrailPackAnswerTest < Minitest::Test
  include RubricLLM::Assertions

  def setup
    @question = "What does the Acme Trail Pack warranty cover?"
    @context = [
      "The Acme Trail Pack includes a lifetime warranty for manufacturing defects.",
      "The warranty does not cover normal wear, misuse, or cosmetic damage."
    ]
    @ground_truth = "The warranty covers manufacturing defects, but not normal wear, misuse, or cosmetic damage."
    @answer = "The Acme Trail Pack has a lifetime warranty for manufacturing defects. " \
              "It does not cover normal wear, misuse, or cosmetic damage."
  end

  def test_answer_is_faithful_to_context
    assert_faithful @answer, @context, question: @question, threshold: 0.8
  end

  def test_answer_is_correct_for_ground_truth
    assert_correct @answer, @ground_truth, question: @question, threshold: 0.8
  end
end
