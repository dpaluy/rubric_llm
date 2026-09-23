---
name: rubric-llm
description: Use RubricLLM to evaluate LLM answers and RAG systems in Ruby, configure judge models and thinking effort, measure retrieval quality, compare evaluation reports, and add quality assertions to tests.
---

# RubricLLM Usage

## Choose the evaluation

RubricLLM scores supplied answers. It does not generate candidate answers or retrieve documents.

1. Inspect the application's gem versions and existing RubyLLM configuration.
2. Select metrics for the available question, answer, context, and reference answer.
3. Configure the judge separately from the model that generates answers.
4. Evaluate a small representative dataset before increasing concurrency or reasoning effort.
5. Check errors and missing scores before interpreting averages or pass/fail results.

Judge calls send data to the selected provider and can incur charges. Do not run live evaluations without permission. Keep credentials in environment variables or the application's secret store. Do not commit sensitive prompts, answers, or reports.

## Install and configure

This guide targets RubricLLM 0.7.x, RubyLLM 2.x, and Ruby 3.4 or later. Thinking effort requires RubricLLM 0.7.0 or later. Check the installed version before using it. Applications on RubyLLM 1.x must remain on RubricLLM 0.5.x unless an upgrade is authorized.

```ruby
# Gemfile
gem "rubric_llm", "~> 0.7.0"
gem "ruby_llm", "~> 2.0"
```

Configure provider credentials through RubyLLM, not RubricLLM. Reuse the application's credential setup.

```ruby
require "rubric_llm"

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY")
end

judge_config = RubricLLM::Config.new(
  judge_model: "gpt-6-astra",
  judge_provider: :openai,
  temperature: nil,
  thinking_effort: :high
)
```

This is a reasoning-model example, not a required model or effort. Confirm model availability and supported controls with the provider. Set the provider explicitly when changing providers.

Use `RubricLLM.configure { |config| ... }` for application-wide settings. Pass a `RubricLLM::Config` as `config:` for individual or batch evaluations. A new `Config` reads its own defaults and environment variables; it does not copy global configuration. To copy the global settings, use `RubricLLM::Config.new(**RubricLLM.config.to_h)`.

| Setting | Environment variable | Default |
| --- | --- | --- |
| `judge_model` | `RUBRIC_JUDGE_MODEL` | `gpt-4o` |
| `judge_provider` | `RUBRIC_JUDGE_PROVIDER` | `openai` |
| `temperature` | `RUBRIC_TEMPERATURE` | `0.0` |
| `thinking_effort` | `RUBRIC_THINKING_EFFORT` | `nil` |
| `max_tokens` | `RUBRIC_MAX_TOKENS` | `4096` |
| `max_retries` | `RUBRIC_MAX_RETRIES` | `2` |
| `retry_base_delay` | `RUBRIC_RETRY_BASE_DELAY` | `1.0` seconds |
| `concurrency` | `RUBRIC_CONCURRENCY` | `1` |

### Thinking effort and token limits

- `thinking_effort` accepts a non-empty string or symbol. RubricLLM passes it to RubyLLM's `with_thinking(effort: ...)` without translating the value.
- Supported values depend on the model and provider. Do not apply a universal list or silently substitute another effort.
- An omitted setting reads `RUBRIC_THINKING_EFFORT`. Explicit `thinking_effort: nil` ignores that variable and leaves thinking controls unset. It does not disable reasoning.
- Use `:none` only for models that support it. Boolean `false` is not a valid RubricLLM effort.
- Explicit `temperature: nil` leaves temperature unset in the provider request. A temperature of zero does not guarantee repeatable scores.
- Higher effort can increase cost and latency. Measure quality on the evaluation dataset rather than assuming improvement.
- Some providers count reasoning tokens within `max_tokens`. Increase the limit if reasoning leaves insufficient space for the JSON score response.

RubyLLM 2 selects the OpenAI Responses protocol for supported models. For a gateway that only supports Chat Completions, configure `RubyLLM.configure { |config| config.openai_protocol = :chat_completions }`.

## Select metrics and score answers

All judge scores are between 0.0 and 1.0, with higher scores indicating better results. Pass metric classes, not names, in `metrics:`.

| Class under `RubricLLM::Metrics` | Purpose | Required evaluation data |
| --- | --- | --- |
| `Relevance` | Answer addresses the question | Question and answer |
| `Faithfulness` | Answer claims are supported by context | Answer and non-empty context |
| `Correctness` | Answer matches a reference | Answer and ground truth |
| `FactualAccuracy` | Answer has no factual discrepancies from a reference | Answer and ground truth |
| `ContextPrecision` | Retrieved chunks are relevant | Question and non-empty context |
| `ContextRecall` | Retrieved chunks cover reference facts | Non-empty context and ground truth |

`evaluate` requires `question:` and `answer:` even when a metric does not use both. If `metrics:` is omitted, all six default metrics run; metrics without required data can return nil scores. Prefer an explicit metric list when data is limited.

```ruby
result = RubricLLM.evaluate(
  question: "What is Ruby?",
  answer: "Ruby is a programming language.",
  context: ["Ruby is a programming language."],
  ground_truth: "A programming language.",
  metrics: [RubricLLM::Metrics::Faithfulness, RubricLLM::Metrics::Correctness],
  config: judge_config
)

raise "Evaluation failed: #{result.errors}" unless result.valid?
raise "Missing metric score" if result.scores.values.any?(&:nil?)

result.scores
result.details
result.overall
result.pass?(threshold: 0.8)
```

`overall` averages only non-nil scores and returns nil if none exist. `valid?` checks reported errors, not score completeness. `pass?` requires no reported errors and an overall score at or above the threshold; it does not require every metric to pass. Check each required score separately when that is the acceptance rule.

Judge failures during `evaluate` become nil metric scores with errors in `result.errors` and `result.details`. Do not treat them as low-quality answers or successful evaluations. Configuration errors can raise. RubricLLM retries selected transient judge failures; RubyLLM has its own retry layer, so combined request counts can exceed `max_retries`.

Use `custom_prompt:` on `evaluate` or `evaluate_batch` for additional judge instructions. Do not include secrets in those instructions.

## Batch evaluation and comparison

```ruby
dataset = [
  { question: "What is Ruby?", answer: "A programming language.",
    ground_truth: "A programming language." }
]

report = RubricLLM.evaluate_batch(
  dataset,
  metrics: [RubricLLM::Metrics::Correctness],
  config: judge_config,
  concurrency: 1
)
puts report.summary
report.failures(threshold: 0.8)
report.worst(3)
```

Each sample must have a non-nil question and answer. Increase concurrency only within provider rate limits and the approved spend. Export with `report.export_json(path)` or `report.export_csv(path)` only to an approved destination.

To compare candidate systems, generate answers for the same questions with each system, then evaluate both datasets with the same judge configuration, metrics, and reference data. Changing only `judge_model` compares judges, not answer-generating systems.

```ruby
comparison = RubricLLM.compare(report_a, report_b)
puts comparison.summary
comparison.significant_improvements
comparison.significant_regressions
```

Reports pair by `sample[:question]`, not array position. Use stable, preferably unique questions. Unmatched questions and excess duplicates are dropped with warnings. Significance uses Holm-Bonferroni-adjusted p-values. Small datasets and statistical significance alone do not establish practical quality improvements.

## Retrieval metrics without a judge

Use document identifiers to evaluate retrieval directly. No provider key or LLM call is required.

```ruby
retrieval = RubricLLM.evaluate_retrieval(
  retrieved: ["doc_a", "doc_b", "doc_c"],
  relevant: ["doc_a", "doc_c"]
)
retrieval.precision_at_k(3)
retrieval.recall_at_k(3)
retrieval.mrr
retrieval.ndcg
retrieval.hit_rate
```

## Tests and custom metrics

For Minitest, require `rubric_llm/minitest` and include `RubricLLM::Assertions`:

```ruby
assert_faithful answer, context, threshold: 0.8, config: judge_config
assert_correct answer, ground_truth, threshold: 0.9, config: judge_config
assert_relevant question, answer, config: judge_config
refute_hallucination answer, context, config: judge_config
```

Faithfulness and hallucination assertions require non-empty context. These assertions call the judge unless stubbed. Keep unit tests offline; in this repository, use `RubyLLMStub` from `test/test_helper.rb`. That stub is not part of the installed gem. Run live quality checks separately with explicit authorization.

For RSpec, require `rubric_llm/rspec` and include `RubricLLM::RSpecMatchers`. Matchers include `be_faithful_to(context)`, `be_correct_for(ground_truth)`, `be_relevant_to(question)`, and `hallucinate_from(context)`.

Custom metrics subclass `RubricLLM::Metrics::Base`, implement `call`, and return `{ score: numeric_score, details: {} }`. Use `judge_eval(system_prompt:, user_prompt:)` for judged metrics; its response must contain a numeric `score` between 0.0 and 1.0. Prefer deterministic checks when no judge is needed.

## References

Consult the repository README and `examples/` for complete workflows. Verify version-sensitive provider behavior against the [RubyLLM documentation](https://rubyllm.com/) and the provider's documentation. Do not assume a model supports every reasoning level, temperature, or structured-output option.
