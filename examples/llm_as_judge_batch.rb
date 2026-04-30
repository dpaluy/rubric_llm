# frozen_string_literal: true

# Score a small RAG dataset and inspect aggregate LLM-as-Judge results.
#
# Run from the project root after configuring RubyLLM provider credentials:
#
#   OPENAI_API_KEY=... bundle exec ruby examples/llm_as_judge_batch.rb

require "rubric_llm"

warn "OPENAI_API_KEY is not set. If RubyLLM is not configured another way, judge calls will fail." unless ENV.key?("OPENAI_API_KEY")

JUDGE_MODEL = "gpt-4.1"
EVALUATED_SYSTEM = "acme-rag-v1 (pre-generated batch outputs)"
FAILURE_THRESHOLD = 0.8

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
end

RubricLLM.configure do |config|
  config.judge_model = JUDGE_MODEL
  config.judge_provider = :openai
end

metrics = [
  RubricLLM::Metrics::Faithfulness,
  RubricLLM::Metrics::Correctness
]

def format_score(score)
  score.nil? ? "n/a" : format("%.2f", score)
end

def score_summary(result)
  metric_scores = result.scores.map do |metric, score|
    "#{metric}=#{format_score(score)}"
  end

  "overall=#{format_score(result.overall)} (#{metric_scores.join(", ")})"
end

def decision_label(result, threshold)
  result.pass?(threshold:) ? "PASS" : "FAIL"
end

def print_sample_result(result, index, threshold)
  puts "#{index}. #{decision_label(result, threshold)} - #{result.sample[:question]}"
  puts "   scores: #{score_summary(result)}"
  puts "   answer: #{result.sample[:answer]}"
end

dataset = [
  {
    question: "What does the Acme Trail Pack warranty cover?",
    context: [
      "The Acme Trail Pack includes a lifetime warranty for manufacturing defects.",
      "The warranty does not cover normal wear, misuse, or cosmetic damage."
    ],
    ground_truth: "The warranty covers manufacturing defects, but not normal wear, misuse, or cosmetic damage.",
    answer: "The Acme Trail Pack has a lifetime warranty for manufacturing defects, excluding normal wear, misuse, and cosmetic damage."
  },
  {
    question: "Can the Acme Trail Pack be machine-washed?",
    context: [
      "Clean the Acme Trail Pack with mild soap and cold water.",
      "Do not machine-wash, bleach, or tumble-dry the pack."
    ],
    ground_truth: "No. It should be cleaned with mild soap and cold water, not machine-washed.",
    answer: "Yes. The Acme Trail Pack can be machine-washed on a hot cycle and tumble-dried."
  },
  {
    question: "What is the Acme Trail Pack made from?",
    context: [
      "The shell uses recycled nylon ripstop.",
      "The lining uses recycled polyester."
    ],
    ground_truth: "The shell is recycled nylon ripstop, and the lining is recycled polyester.",
    answer: "It uses recycled nylon ripstop for the shell and recycled polyester for the lining."
  }
]

report = RubricLLM.evaluate_batch(dataset, metrics:, concurrency: 2)

puts "Judge model: #{JUDGE_MODEL}"
puts "Evaluated system: #{EVALUATED_SYSTEM}"
puts
puts report.summary
puts <<~TEXT

  How to read this:
  - The judge model scores pre-generated answers from the evaluated system; this script does not call the evaluated system.
  - faithfulness checks whether the answer is supported by the context.
  - correctness checks whether the answer matches the ground truth.
  - Each sample's overall score is the average of its metric scores, so faithfulness=0.00 and correctness=0.00 means overall=0.00.
  - PASS means the sample's overall score is at least #{format("%.2f", FAILURE_THRESHOLD)}; FAIL means it is below that threshold.
  - Report stats summarize each metric across all samples; results below #{format("%.2f", FAILURE_THRESHOLD)} are listed for review.
TEXT

puts "\nSample results:"
report.results.each_with_index do |result, index|
  print_sample_result(result, index + 1, FAILURE_THRESHOLD)
end

puts "\nFailures below #{format("%.2f", FAILURE_THRESHOLD)}:"
report.failures(threshold: FAILURE_THRESHOLD).each do |result|
  puts "- #{result.sample[:question]}"
  puts "  scores: #{score_summary(result)}"
end

puts "\nWorst sample:"
worst = report.worst(1).first
puts worst.sample[:question]
puts "scores: #{score_summary(worst)}"
