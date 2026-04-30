# frozen_string_literal: true

# Evaluate two RAG answers with live LLM-as-Judge calls.
#
# Run from the project root after configuring RubyLLM provider credentials, for example:
#
#   OPENAI_API_KEY=... bundle exec ruby examples/llm_as_judge_rag.rb
#
# Scores vary by judge model. The candidate outputs intentionally differ in
# quality; let the judge scores decide which one passes and which needs review.

require "rubric_llm"

warn "OPENAI_API_KEY is not set. If RubyLLM is not configured another way, judge calls will fail." unless ENV.key?("OPENAI_API_KEY")

JUDGE_MODEL = "gpt-4.1"
EVALUATED_SYSTEM = "acme-rag-v1 (pre-generated candidate answers)"

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

RubricLLM.configure do |config|
  config.judge_model = JUDGE_MODEL
  config.judge_provider = :openai
end

EVALUATION_METRICS = [
  RubricLLM::Metrics::Faithfulness,
  RubricLLM::Metrics::Correctness
].freeze

def format_score(score)
  score.nil? ? "n/a" : format("%.2f", score)
end

def metric_error(details)
  return unless details.is_a?(Hash)

  details[:error] || details["error"] || metric_error(details[:details] || details["details"])
end

def print_metric_errors(result)
  errors = result.details.filter_map do |metric, details|
    error = metric_error(details)
    [metric, error] if error
  end

  return if errors.empty?

  puts "errors:"
  errors.each { |metric, error| puts "  #{metric}: #{error}" }
end

question = "What does the Acme Trail Pack warranty cover?"
context = [
  "The Acme Trail Pack includes a lifetime warranty for manufacturing defects.",
  "The warranty does not cover normal wear, misuse, or cosmetic damage."
]
ground_truth = "The pack has a lifetime warranty for manufacturing defects, " \
               "but not normal wear, misuse, or cosmetic damage."

candidate_answers = [
  {
    id: "candidate-a",
    answer: "The Acme Trail Pack has a lifetime warranty for manufacturing defects. " \
            "It does not cover normal wear, misuse, or cosmetic damage."
  },
  {
    id: "candidate-b",
    answer: "The Acme Trail Pack has a lifetime warranty for manufacturing defects. " \
            "It also covers airline damage and cosmetic zipper repairs."
  }
]

puts "Judge model: #{JUDGE_MODEL}"
puts "Evaluated system: #{EVALUATED_SYSTEM}"

candidate_answers.each do |candidate|
  answer = candidate.fetch(:answer)
  result = RubricLLM.evaluate(question:, answer:, context:, ground_truth:, metrics: EVALUATION_METRICS)

  puts "\n#{candidate.fetch(:id)}"
  puts "answer: #{answer}"
  puts "overall:      #{format_score(result.overall)}"
  puts "faithfulness: #{format_score(result.faithfulness)}"
  puts "correctness:  #{format_score(result.correctness)}"
  puts result.pass?(threshold: 0.8) ? "decision: pass" : "decision: review"
  print_metric_errors(result)
end
