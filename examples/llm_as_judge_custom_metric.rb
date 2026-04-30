# frozen_string_literal: true

# Define a custom LLM-as-Judge metric for product-support answers.
#
# Run from the project root after configuring RubyLLM provider credentials:
#
#   OPENAI_API_KEY=... bundle exec ruby examples/llm_as_judge_custom_metric.rb

require "rubric_llm"

warn "OPENAI_API_KEY is not set. If RubyLLM is not configured another way, judge calls will fail." unless ENV.key?("OPENAI_API_KEY")

JUDGE_MODEL = "gpt-4.1"
EVALUATED_SYSTEM = "support-answer-generator-v1 (pre-generated answers)"

question = "Can I return a backpack after using it on a trip?"
candidate_answers = [
  {
    id: "candidate-a",
    answer: "Used gear cannot be returned unless there is a manufacturing defect. " \
            "If you think your pack is defective, send us photos and your order number so we can review it."
  },
  {
    id: "candidate-b",
    answer: "No. You used it, so that is your problem. Do not contact support about this again."
  }
]

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

RubricLLM.configure do |config|
  config.judge_model = JUDGE_MODEL
  config.judge_provider = :openai
end

class HelpfulSupportTone < RubricLLM::Metrics::Base
  SYSTEM_PROMPT = <<~PROMPT
    You are an evaluation judge. Score whether the answer is clear, concise, and professionally helpful for customer support.

    Respond with JSON only:
    {
      "score": <float 0.0-1.0>,
      "reasoning": "<brief explanation>"
    }
  PROMPT

  def call(question:, answer:, **)
    result = judge_eval(
      system_prompt: SYSTEM_PROMPT,
      user_prompt: "Customer question: #{question}\n\nSupport answer: #{answer}"
    )

    return { score: nil, details: result } unless result.is_a?(Hash) && result["score"]

    {
      score: Float(result["score"]).clamp(0.0, 1.0),
      details: { reasoning: result["reasoning"] }
    }
  end
end

puts "Judge model: #{JUDGE_MODEL}"
puts "Evaluated system: #{EVALUATED_SYSTEM}"

candidate_answers.each do |candidate|
  answer = candidate.fetch(:answer)
  result = RubricLLM.evaluate(question:, answer:, metrics: [HelpfulSupportTone])
  score = result.scores[:helpful_support_tone]

  puts "\n#{candidate.fetch(:id)}"
  puts "answer: #{answer}"
  puts "helpful support tone: #{score.nil? ? "n/a" : format("%.2f", score)}"
  puts "reasoning: #{result.details.dig(:helpful_support_tone, :reasoning) || "n/a"}"
  puts result.pass?(threshold: 0.8) ? "decision: pass" : "decision: review"
end
