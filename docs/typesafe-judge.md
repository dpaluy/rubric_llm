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

## Measurement differences

System One cannot generate claims. Faithfulness, factual accuracy, and context recall therefore split text deterministically into sentences and ask one noul per sentence. This is a different measurement from the chat judge's generated claim extraction, not an equivalent implementation. Every sentence is processed in chunks of `typesafe_sentence_limit` (default 40).

System One confidence describes concentration of the returned probability distribution. It does **not** establish that an answer is correct. The default cascade policy uses confidence and the configured noul uncertainty band only to decide when another judge should review a metric.

System One details retain the resolved model, token usage, latency, probability distributions, typed answers, and every raw chunk response. Cascade details additionally retain the System One attempt, escalation decision and reason, and fallback error when chat fails. `Report#summary`, CSV, and JSON expose per-metric escalation counts. `Report#total_usage` adds System One and chat fallback usage; it returns `nil` when any attempted call has unknown usage rather than presenting a partial count as a complete total. JSON exports include `usage_complete` when usage was attempted.

TypeSafe documents model-specific request budgets (currently 64k total request tokens and 32k for state plus the longest question for listed Jev models) and dynamic rate limits. Consult [TypeSafe models](https://docs.typesafe.ai/models) rather than assuming a byte limit.

## Calibration

Thresholds must be revalidated whenever a pinned `jev-*` version changes. Run:

```sh
ruby examples/typesafe_calibration.rb path/to/your-dataset.json
```

The JSON file must be an array of objects accepted by `RubricLLM.evaluate_batch`, with `question`, `answer`, and the `context`/`ground_truth` required by selected metrics. The script runs chat, System One, and cascade; prints all three pairwise comparisons; reports actual provider token usage, wall time, and escalation rates; and reports per-metric Pearson correlation and mean absolute difference. Missing pairs and constant series print `n/a` rather than a fabricated statistic.

No labeled calibration dataset ships with the gem. The project test exercises this harness only with disposable synthetic/offline reports and makes no API calls.
