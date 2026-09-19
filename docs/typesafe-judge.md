# TypeSafe System One judge

RubricLLM supports three judge backends:

- `:chat` (default) keeps the existing RubyLLM prompts and response contracts.
- `:system_one` sends typed choice, score, and noul questions to TypeSafe System One.
- `:cascade` runs System One first and falls back to chat for uncertain answers or System One failures.

```ruby
RubricLLM.configure do |config|
  config.judge_backend = :cascade
  config.typesafe_api_key = ENV.fetch("TYPESAFE_API_KEY")
  config.typesafe_model = "jev-1.13.0" # pin the version calibrated by your team
  config.cascade_confidence = 0.70
  config.cascade_noul_band = 0.35..0.65
end
```

Use chat when you need the established claim-extraction behavior. Use System One for low-latency typed judgments and full probability distributions. Use cascade when most samples can use System One but uncertain cases need the chat judge. A custom policy may be supplied as `config.cascade_policy = ->(response) { ... }`; it receives the actual `RubricLLM::SystemOne::Response` for each request. Returning truthy escalates that metric.

The Minitest assertions and RSpec matchers honor `config.judge_backend`. A helper configured for `:system_one` or `:cascade` uses that backend instead of creating a chat judge.

## Measurement differences

System One cannot generate claims. Faithfulness, factual accuracy, and context recall therefore split text deterministically into sentences and ask one noul per sentence. This is a different measurement from the chat judge's generated claim extraction, not an equivalent implementation. Every sentence is processed in chunks of `typesafe_sentence_limit` (default 40). Each faithfulness chunk retains the question and complete answer. Each context-recall chunk retains the complete ground truth. This state lets a sentence such as `Yes.` or a later pronoun keep its source meaning.

`custom_prompt` is added to every typed question. Its additional instructions do not replace the metric's base instructions or structured criteria.

System One confidence describes concentration of the returned probability distribution. It does **not** establish that an answer is correct. The default cascade policy uses confidence and the configured noul uncertainty band only to decide when another judge should review a metric.

System One details retain the resolved model, token usage, latency, probability distributions, typed answers, and every raw chunk response. Cascade details additionally retain the System One attempt, escalation decision and reason, and fallback error when chat fails. `Report#summary`, CSV, and JSON expose per-metric escalation counts. A skipped metric is excluded from the escalation denominator.

Usage attempts are recorded at the judge call boundary, including calls from legacy custom metrics. `Report#total_usage` adds System One and chat fallback usage. It returns `nil` when any attempted call has unknown input or output usage. `Report#usage_by_model` groups calls by backend, provider, and model so Jev and chat use remain separate. Each group reports `usage_complete`; incomplete groups have an unknown token total. JSON exports include the same usage fields.

TypeSafe transport retries are recorded separately. A timeout followed by a successful retry leaves the total unknown because the timed-out request may have consumed tokens. The successful response's usage remains available in the attempt records.

TypeSafe documents model-specific request budgets (currently 64k total request tokens and 32k for state plus the longest question for listed Jev models) and dynamic rate limits. Consult [TypeSafe models](https://docs.typesafe.ai/models) rather than assuming a byte limit.

## Calibration

Thresholds must be revalidated whenever a pinned `jev-*` version changes. Run:

```sh
ruby examples/typesafe_calibration.rb path/to/your-dataset.json
```

The JSON file must be an array of objects accepted by `RubricLLM.evaluate_batch`, with `question`, `answer`, and the `context` or `ground_truth` required by selected metrics. Optional `expected_judgments` values label whether each metric should pass:

```json
{
  "question": "Is the sky blue?",
  "answer": "Yes.",
  "context": ["The sky is blue."],
  "expected_judgments": {
    "relevance": true,
    "faithfulness": true
  }
}
```

Labels must be booleans. Set explicit per-metric pass thresholds from Ruby. Metrics omitted from the map use `RubricLLM::DEFAULT_THRESHOLD`:

```ruby
require "json"
require_relative "examples/typesafe_calibration"

dataset = JSON.parse(File.read("path/to/your-dataset.json"), symbolize_names: true)
TypeSafeCalibration.run(dataset, thresholds: { relevance: 0.75, faithfulness: 0.85 })
```

The script runs chat, System One, and cascade. It prints all pairwise comparisons, total usage, usage grouped by backend/provider/model, wall time, escalation rates, Pearson correlation, and mean absolute difference. Agreement with chat does not prove correctness. When labels are absent, the script states that quality is unknown.

For labeled data, the script reports accuracy over scored labels, missing scores, and false passes over labeled automatic passes. An automatic pass is a System One pass or a cascade pass with `escalated: false`. Missing scores, skipped metrics, and escalated chat fallbacks do not enter that false-pass denominator. A zero denominator prints `n/a`.

Use one calibration split to select thresholds and cascade settings. Measure the chosen settings once on a separate held-out split. Report errors, missing scores, and abstentions separately from scored accuracy. Do not fit confidence thresholds and report quality on the same samples.

No labeled calibration dataset ships with the gem. The project test exercises this harness only with disposable synthetic/offline reports and makes no API calls.
