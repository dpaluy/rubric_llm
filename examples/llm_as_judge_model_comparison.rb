# frozen_string_literal: true

# Compare outputs from two evaluated RAG systems with the same judge model.
#
# RubricLLM does not call the evaluated models here. The two datasets contain
# pre-generated answers from each system. The judge model scores those answers.
#
# Run from the project root after configuring RubyLLM provider credentials:
#
#   OPENAI_API_KEY=... bundle exec ruby examples/llm_as_judge_model_comparison.rb

require "rubric_llm"

warn "OPENAI_API_KEY is not set. If RubyLLM is not configured another way, judge calls will fail." unless ENV.key?("OPENAI_API_KEY")

JUDGE_MODEL = "gpt-4.1"
BASELINE_SYSTEM = "acme-rag-v1 (pre-generated baseline outputs)"
CANDIDATE_SYSTEM = "acme-rag-v2 (pre-generated candidate outputs)"

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

samples = [
  {
    question: "What does the Acme Trail Pack warranty cover?",
    context: [
      "The Acme Trail Pack includes a lifetime warranty for manufacturing defects.",
      "The warranty does not cover normal wear, misuse, or cosmetic damage."
    ],
    ground_truth: "The warranty covers manufacturing defects, but not normal wear, misuse, or cosmetic damage.",
    baseline_answer: "The Acme Trail Pack has a lifetime warranty for manufacturing defects, and it also covers normal wear.",
    candidate_answer: "The Acme Trail Pack has a lifetime warranty for manufacturing defects, " \
                      "excluding normal wear, misuse, and cosmetic damage."
  },
  {
    question: "Can the Acme Trail Pack be machine-washed?",
    context: [
      "Clean the Acme Trail Pack with mild soap and cold water.",
      "Do not machine-wash, bleach, or tumble-dry the pack."
    ],
    ground_truth: "No. It should be cleaned with mild soap and cold water, not machine-washed.",
    baseline_answer: "Clean it with mild soap and cold water, then tumble-dry it on low heat.",
    candidate_answer: "No. Clean it with mild soap and cold water, and do not machine-wash or tumble-dry it."
  },
  {
    question: "What is the Acme Trail Pack made from?",
    context: [
      "The shell uses recycled nylon ripstop.",
      "The lining uses recycled polyester."
    ],
    ground_truth: "The shell is recycled nylon ripstop, and the lining is recycled polyester.",
    baseline_answer: "The shell uses recycled nylon ripstop, and the lining is cotton canvas.",
    candidate_answer: "It uses recycled nylon ripstop for the shell and recycled polyester for the lining."
  }
]

baseline_dataset = samples.map { |sample| sample.except(:baseline_answer, :candidate_answer).merge(answer: sample[:baseline_answer]) }
candidate_dataset = samples.map { |sample| sample.except(:baseline_answer, :candidate_answer).merge(answer: sample[:candidate_answer]) }

baseline_report = RubricLLM.evaluate_batch(baseline_dataset, metrics:, concurrency: 2)
candidate_report = RubricLLM.evaluate_batch(candidate_dataset, metrics:, concurrency: 2)
comparison = RubricLLM.compare(baseline_report, candidate_report)

puts "Judge model: #{JUDGE_MODEL}"
puts "Baseline evaluated system: #{BASELINE_SYSTEM}"
puts "Candidate evaluated system: #{CANDIDATE_SYSTEM}"

puts "\nBaseline report:"
puts baseline_report.summary

puts "\nCandidate report:"
puts candidate_report.summary

puts "\nComparison:"
puts comparison.summary
