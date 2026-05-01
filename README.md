# RubricLLM

Lightweight LLM evaluation framework for Ruby, inspired by [DeepEval](https://github.com/confident-ai/deepeval), powered by [RubyLLM](https://github.com/crmne/ruby_llm).

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
  question: "What is Ruby's core design philosophy?",
  answer: "Ruby was designed by Yukihiro Matsumoto to optimize for developer happiness and productivity, prioritizing the programmer's joy over machine efficiency.",
  context: [
    "Yukihiro Matsumoto, Ruby's creator, has stated that Ruby is designed to make programmers happy. " \
    "He optimized the language for human readability and developer productivity rather than raw machine performance."
  ],
  ground_truth: "Ruby is designed to maximize developer happiness and productivity."
)

result.correctness       # => 0.99
result.pass?             # => true
```

For runnable LLM-as-Judge examples, including RAG scoring, batch pass/fail output, model comparison, custom metrics, and live
Minitest assertions, see [examples/README.md](examples/README.md).

## Configuration

### Global

```ruby
RubricLLM.configure do |c|
  c.judge_model = "gpt-5.5"           # any model RubyLLM supports
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
custom = RubricLLM::Config.new(judge_model: "claude-opus-4-5", judge_provider: :anthropic)

result = RubricLLM.evaluate(question: "...", answer: "...", config: custom)
report = RubricLLM.evaluate_batch(dataset, config: custom)
```

### Rails Setup

```ruby
# config/initializers/rubric_llm.rb
RubricLLM.configure do |c|
  c.judge_model = "gpt-5.5"
  c.judge_provider = :openai
end
```

## Metrics

### LLM-as-Judge Metrics

These metrics use a judge LLM to evaluate quality. Each sends a structured prompt and parses a JSON response with a 0.0–1.0 score.

| Metric | Question it answers | Requires |
|--------|-------------------|----------|
| **Correctness** | Does the answer match the known correct answer? | `ground_truth` |
| **Relevance** | Does the answer address what was asked? | `question` |
| **Context Precision** | Are the retrieved context chunks actually relevant? | `question`, `context` |
| **Factual Accuracy** | Are there factual discrepancies between candidate and reference? | `ground_truth` |
| **Context Recall** | Do the contexts cover the information in the ground truth? | `context`, `ground_truth` |
| **Faithfulness** | Is every claim in the answer supported by the context? | `context` |

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
result.recall_at_k(3)     # => 0.90
result.mrr                # => 0.90
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
config_a = RubricLLM::Config.new(judge_model: "gpt-5.5")
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

- **Cross-model judging.** Configure a different model as judge than the one being evaluated. Don't let gpt-5.5 grade gpt-5.5.
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

## Understanding A/B Comparison

The "A/B comparison" row above mentions **paired t-tests with p-values**. Here's why that matters.

### The problem it solves

You evaluate Model A and Model B on the same 50 questions. A averages 0.85, B averages 0.88. Is B genuinely better, or did it just get lucky on a few questions?

Eyeballing means won't tell you. You need to know if the **difference is bigger than the run-to-run noise**.

### Paired t-test

A t-test compares two sets of numbers and tells you how likely it is that the difference between their means is real vs. random noise.

**Paired** means each sample in A has a matching sample in B — same question, scored by both models. Instead of comparing the two distributions independently, the test looks at the *per-question difference* (B's score − A's score on question 1, on question 2, …) and asks: "is the average difference reliably non-zero?"

Pairing matters because some questions are just harder than others. If you ignore the pairing, that question-level noise drowns out the model-level signal. A paired test removes it — you only care that B beats A *on the same items*.

### p-value

The p-value is the probability of seeing a difference at least this large **if the two models were actually equivalent**. Small p = unlikely to be coincidence = you can trust the difference is real.

Conventional thresholds (the `*` markers in the A/B comparison output):

- `p < 0.05` (`*`) — less than 5% chance it's noise. Standard "significant".
- `p < 0.01` (`**`) — less than 1%. Strong evidence.
- `p < 0.001` (`***`) — less than 0.1%. Very strong.

### Reading the example output

From the A/B comparison example earlier in this README:

```
faithfulness   0.880  0.920  +0.040  p=0.0230  *
relevance      0.850  0.860  +0.010  p=0.4210
correctness    0.910  0.940  +0.030  p=0.0089  **
```

- **faithfulness**: B is +0.040 better, p=0.023 → real improvement, ship it.
- **relevance**: +0.010 looks like a win but p=0.42 → 42% chance this is just noise. Don't claim B is better at relevance.
- **correctness**: +0.030 with p=0.0089 → strong evidence B is genuinely more correct.

### Why this matters

Without it, A/B comparison is vibes. You'd ship a model swap based on a 0.01 mean difference that's pure noise, or reject a real improvement because it looked small. The paired t-test is what makes "Model B is better" a defensible claim instead of an opinion.

**Caveat**: the test assumes the per-question score *differences* are roughly normally distributed. With small datasets (n < 20) or score distributions full of 0s and 1s, p-values get unreliable. For those cases the proper tool is a Wilcoxon signed-rank test — same idea, no normality assumption.

## Why Retrieval Metrics Are Pure Math

The Limitations section calls retrieval metrics "pure math." That's not just marketing — it's a meaningful guarantee. Here's what it means and why it matters.

### What "pure math" means

`precision_at_k`, `recall_at_k`, `mrr`, `ndcg`, and `hit_rate` are computed from two inputs and nothing else: the list of retrieved document IDs, and the list of known-relevant document IDs. The implementation is set arithmetic and basic algebra — no LLM call, no embedding model, no API key, no network.

Given the same inputs, you get the same output. Forever. On any machine.

### What each metric actually computes

Using the example from the Retrieval Metrics section above (`retrieved: [a, b, c, d]`, `relevant: [a, c]`):

- **`precision_at_k(3)`** — Of the top 3 retrieved (`a, b, c`), how many are in the relevant set? 2 out of 3 → **0.67**. Answers: "how much of what I showed the user was useful?"
- **`recall_at_k(3)`** — Of the relevant docs (`a, c`), how many appear in the top 3? Both → **1.0**. Answers: "did I find the things that exist?"
- **`mrr`** (Mean Reciprocal Rank) — 1 ÷ (rank of first relevant doc). `a` is at position 1, so 1/1 = **1.0**. Answers: "how fast does the user hit something useful?"
- **`ndcg`** (Normalized Discounted Cumulative Gain) — Like recall, but rewards putting relevant docs *higher* in the list. A relevant doc at rank 1 is worth more than one at rank 4. Output is normalized to 0–1.
- **`hit_rate`** — Did at least one relevant doc appear in the results? **1.0** (yes) or **0.0** (no). Coarse but honest.

None of these need a model to "judge" anything. They're definitions, not opinions.

### Why this matters

Every other metric in this gem uses an LLM as judge, which means they inherit the judge's failure modes — hallucination, prompt sensitivity, model drift, cost per call, rate limits. That's the deal you accept for getting a score on something subjective like "is this answer faithful?"

Retrieval is different because the question — *did the right documents come back?* — has a ground-truth answer the moment you label your eval set. No judgment call required. So:

- **No judge bias.** A different model can't disagree with your numbers.
- **No API cost.** Run it 10,000 times on every CI build. It's free.
- **Deterministic.** Same retriever + same eval set = same score, every time. Regressions are unambiguous.
- **Fast.** Microseconds per query. Not seconds.
- **Works offline.** No network, no keys, no provider outages.

### When to reach for retrieval metrics

If you're building RAG and you're not measuring retrieval separately from generation, you're flying blind. A bad answer can come from a great retriever (the LLM mangled good context) or a great LLM (it had nothing useful to work with). LLM-as-judge metrics blur the two. Retrieval metrics isolate the retriever so you know which half to fix.

Pair them: use retrieval metrics to lock down "are we finding the right docs?", then use LLM-as-judge metrics for "are we using them well?"

## Requirements

- Ruby >= 3.4
- [ruby_llm](https://github.com/crmne/ruby_llm) ~> 1.0
- An API key for your chosen LLM provider (set via RubyLLM configuration)

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/dpaluy/rubric_llm).

## License

[MIT](LICENSE.txt)

Supported by [Majestic Labs](https://majesticlabs.dev/).
