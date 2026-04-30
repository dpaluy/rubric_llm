# RubricLLM

Lightweight LLM evaluation framework for Ruby, inspired by [Ragas](https://github.com/vibrantlabsai/ragas), powered by [RubyLLM](https://github.com/crmne/ruby_llm).

[![Gem Version](https://badge.fury.io/rb/rubric_llm.svg)](https://badge.fury.io/rb/rubric_llm)
[![CI](https://github.com/dpaluy/rubric_llm/actions/workflows/ci.yml/badge.svg)](https://github.com/dpaluy/rubric_llm/actions/workflows/ci.yml)

Provider-agnostic evaluation with pluggable metrics, statistical A/B comparison, and test framework integration — no Rails, no ActiveRecord, no UI. Works anywhere Ruby runs.

## Installation

Add to your Gemfile:

```ruby
gem "rubric_llm"
```

Or install directly:

```bash
gem install rubric_llm
```

## Quick Start

```ruby
require "rubric_llm"

RubricLLM.configure do |c|
  c.judge_model = "gpt-5.5"
  c.judge_provider = :openai
end

result = RubricLLM.evaluate(
  question: "What is the capital of France?",
  answer: "The capital of France is Paris, located on the Seine river.",
  context: ["Paris is the capital and largest city of France."],
  ground_truth: "Paris"
)

result.faithfulness      # => 0.95
result.relevance         # => 0.92
result.correctness       # => 0.98
result.overall           # => 0.94
result.pass?             # => true
```

For runnable LLM-as-Judge examples, including RAG scoring, batch pass/fail output, model comparison, custom metrics, and live
Minitest assertions, see [examples/README.md](examples/README.md).

## Configuration

### Global

```ruby
RubricLLM.configure do |c|
  c.judge_model = "gpt-4o"           # any model RubyLLM supports
  c.judge_provider = :openai          # :openai, :anthropic, :gemini, etc.
  c.temperature = 0.0                 # deterministic scoring (default)
  c.max_tokens = 4096                 # max tokens for judge response
end
```

### Environment Variables

All config fields can be set via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RUBRIC_JUDGE_MODEL` | `gpt-4o` | Judge LLM model name |
| `RUBRIC_JUDGE_PROVIDER` | `openai` | RubyLLM provider |
| `RUBRIC_TEMPERATURE` | `0.0` | Judge temperature |
| `RUBRIC_MAX_TOKENS` | `4096` | Max response tokens |
| `RUBRIC_MAX_RETRIES` | `2` | Max retries on transient failures |
| `RUBRIC_RETRY_BASE_DELAY` | `1.0` | Base delay (seconds) for exponential backoff |
| `RUBRIC_CONCURRENCY` | `1` | Thread pool size for batch evaluation |

```ruby
# Reads all RUBRIC_* env vars automatically
config = RubricLLM::Config.from_env
```

### Per-Evaluation Override

```ruby
custom = RubricLLM::Config.new(judge_model: "claude-haiku-4-5", judge_provider: :anthropic)

result = RubricLLM.evaluate(question: "...", answer: "...", config: custom)
report = RubricLLM.evaluate_batch(dataset, config: custom)
```

### Rails Setup

```ruby
# config/initializers/rubric_llm.rb
RubricLLM.configure do |c|
  c.judge_model = "gpt-4o"
  c.judge_provider = :openai
end
```

## Metrics

### LLM-as-Judge Metrics

These metrics use a judge LLM to evaluate quality. Each sends a structured prompt and parses a JSON response with a 0.0–1.0 score.

| Metric | Question it answers | Requires |
|--------|-------------------|----------|
| **Faithfulness** | Is every claim in the answer supported by the context? | `context` |
| **Relevance** | Does the answer address what was asked? | `question` |
| **Correctness** | Does the answer match the known correct answer? | `ground_truth` |
| **Context Precision** | Are the retrieved context chunks actually relevant? | `question`, `context` |
| **Context Recall** | Do the contexts cover the information in the ground truth? | `context`, `ground_truth` |
| **Factual Accuracy** | Are there factual discrepancies between candidate and reference? | `ground_truth` |

```ruby
# Only context — gets faithfulness, relevance, context_precision
result = RubricLLM.evaluate(
  question: "How does photosynthesis work?",
  answer: "Plants convert sunlight into energy.",
  context: ["Photosynthesis is the process by which plants convert light energy into chemical energy."]
)

# With ground truth — gets all metrics
result = RubricLLM.evaluate(
  question: "How does photosynthesis work?",
  answer: "Plants convert sunlight into energy.",
  context: ["Photosynthesis is the process by which plants convert light energy into chemical energy."],
  ground_truth: "Plants use photosynthesis to convert sunlight, water, and CO2 into glucose and oxygen."
)
```

### Custom Metrics

```ruby
class ToneMetric < RubricLLM::Metrics::Base
  SYSTEM_PROMPT = "Rate professional tone from 0.0 to 1.0. Respond with JSON: {\"score\": 0.0, \"tone\": \"description\"}"

  def call(answer:, **)
    result = judge_eval(system_prompt: SYSTEM_PROMPT, user_prompt: "Answer: #{answer}")
    return { score: nil, details: result } unless result.is_a?(Hash) && result["score"]

    { score: Float(result["score"]), details: { tone: result["tone"] } }
  end
end

result = RubricLLM.evaluate(
  question: "q", answer: "a",
  metrics: [RubricLLM::Metrics::Faithfulness, ToneMetric]
)
result.scores[:tone_metric]  # => 0.85
```

### Retrieval Metrics

Pure math — no LLM calls, no API key needed.

```ruby
result = RubricLLM.evaluate_retrieval(
  retrieved: ["doc_a", "doc_b", "doc_c", "doc_d"],
  relevant: ["doc_a", "doc_c"]
)

result.precision_at_k(3)  # => 0.67
result.recall_at_k(3)     # => 1.0
result.mrr                # => 1.0
result.ndcg               # => 0.86
result.hit_rate           # => 1.0
```

## Batch Evaluation

Evaluate a dataset and get aggregate statistics:

```ruby
dataset = [
  { question: "What is Ruby?", answer: "A programming language.",
    context: ["Ruby is a dynamic language."], ground_truth: "Ruby is a programming language." },
  { question: "What is Rails?", answer: "A web framework.",
    context: ["Rails is a web framework for Ruby."], ground_truth: "Rails is a Ruby web framework." },
  # ...
]

report = RubricLLM.evaluate_batch(dataset)

# Speed up with concurrent evaluation (thread pool)
report = RubricLLM.evaluate_batch(dataset, concurrency: 4)

puts report.summary
# RubricLLM Evaluation Report
# ========================================
# Samples: 20
# Duration: 45.2s
#   faithfulness          mean=0.920  std=0.050  min=0.850  max=0.980  n=20

report.worst(3)                    # 3 lowest-scoring results
report.failures(threshold: 0.8)   # results below 0.8
report.export_csv("results.csv")      # export to CSV
report.export_json("results.json")    # export to JSON
report.to_json                        # returns JSON string
```

## A/B Model Comparison

Compare two models with statistical significance testing:

```ruby
config_a = RubricLLM::Config.new(judge_model: "gpt-4o")
config_b = RubricLLM::Config.new(judge_model: "claude-sonnet-4-6")

report_a = RubricLLM.evaluate_batch(dataset, config: config_a)
report_b = RubricLLM.evaluate_batch(dataset, config: config_b)

comparison = RubricLLM.compare(report_a, report_b)

puts comparison.summary
# A/B Comparison
# ======================================================================
# Metric                      A        B    Delta    p-value  Sig
# ----------------------------------------------------------------------
# faithfulness                0.880    0.920   +0.040     0.0230    *
# relevance                   0.850    0.860   +0.010     0.4210
# correctness                 0.910    0.940   +0.030     0.0089   **

comparison.significant_improvements   # => [:faithfulness, :correctness]
comparison.significant_regressions    # => []
```

Significance markers: `*` (p < 0.05), `**` (p < 0.01), `***` (p < 0.001)

## Test Integration

### Minitest

```ruby
require "rubric_llm/minitest"

class AdvisorTest < Minitest::Test
  include RubricLLM::Assertions

  def test_answer_is_faithful
    answer = my_llm.ask("What is Ruby?", context: docs)
    assert_faithful answer, docs, threshold: 0.8
  end

  def test_answer_is_correct
    answer = my_llm.ask("What is 2+2?")
    assert_correct answer, "4", threshold: 0.9
  end

  def test_no_hallucination
    answer = my_llm.ask("Summarize this", context: docs)
    refute_hallucination answer, docs
  end

  def test_answer_is_relevant
    answer = my_llm.ask("How do I deploy Rails?")
    assert_relevant "How do I deploy Rails?", answer, threshold: 0.7
  end
end
```

### RSpec

```ruby
require "rubric_llm/rspec"

RSpec.describe "My LLM" do
  include RubricLLM::RSpecMatchers

  let(:answer) { my_llm.ask(question, context: docs) }

  it { expect(answer).to be_faithful_to(docs).with_threshold(0.8) }
  it { expect(answer).to be_relevant_to(question) }
  it { expect(answer).to be_correct_for(expected_answer) }
  it { expect(answer).not_to hallucinate_from(docs) }
end
```

## Error Handling

```ruby
begin
  result = RubricLLM.evaluate(question: "q", answer: "a", context: ["c"])
rescue RubricLLM::JudgeError => e
  # LLM call failed (network, auth, rate limit)
  puts "Judge error: #{e.message}"
rescue RubricLLM::ConfigurationError => e
  # Invalid configuration
  puts "Config error: #{e.message}"
rescue RubricLLM::Error => e
  # Catch-all for any RubricLLM error
  puts "Error: #{e.message}"
end
```

Individual metric failures are handled gracefully — a failed metric returns `nil` for the score and includes the error in details:

```ruby
result = RubricLLM.evaluate(question: "q", answer: "a")
result.scores[:faithfulness]           # => nil (if judge failed)
result.details[:faithfulness][:error]  # => "Judge call failed: ..."
result.overall                         # => mean of non-nil scores only
```

## Development

```bash
bundle install
bundle exec rake test
bundle exec rubocop
```

## Limitations

RubricLLM uses LLM-as-Judge — an LLM scores another LLM's output. This is the industry-standard approach (used by Ragas, DeepEval, ARES), but it means the judge shares the same class of failure modes as the system being evaluated. If the judge hallucinates that an answer is faithful, you get a false positive.

Mitigations built into the framework:

- **Cross-model judging.** Configure a different model as judge than the one being evaluated. Don't let GPT-4o grade GPT-4o.
- **Retrieval metrics are pure math.** `precision_at_k`, `recall_at_k`, `mrr`, `ndcg` — no LLM involved, no judge bias.
- **Custom non-LLM metrics.** Subclass `Metrics::Base` with regex checks, embedding similarity, or any deterministic logic.
- **Statistical comparison.** A/B testing with paired t-tests surfaces systematic judge bias across runs.

For high-stakes evaluation, pair LLM-as-Judge metrics with retrieval metrics and periodic human review.

## Why RubricLLM?

Ruby has two LLM evaluation options today. Neither fits most use cases:

| | [eval-ruby](https://github.com/johannesdwicahyo/eval-ruby) | [leva](https://github.com/kieranklaassen/leva) | RubricLLM |
|---|---|---|---|
| **What it is** | Generic RAG metrics | Rails engine with UI | Lightweight eval framework |
| **LLM access** | Raw HTTP (OpenAI/Anthropic only) | You implement it | RubyLLM (any provider) |
| **Rails required?** | No | Yes (engine + 6 migrations) | No |
| **ActiveRecord?** | No | Yes | No |
| **A/B comparison** | Basic | No | Paired t-test with p-values |
| **Test assertions** | Minitest + RSpec | No | Minitest + RSpec |
| **Pluggable metrics** | No (fixed set) | Yes | Yes |
| **Retrieval metrics** | Yes | No | Yes |

## Requirements

- Ruby >= 3.4
- [ruby_llm](https://github.com/crmne/ruby_llm) ~> 1.0
- An API key for your chosen LLM provider (set via RubyLLM configuration)

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/dpaluy/rubric_llm).

## License

[MIT](LICENSE.txt)

Supported by [Majestic Labs](https://majesticlabs.dev/).
