# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add TypeSafe System One as a typed judge backend for all six judge metrics, with preserved probability distributions, usage, latency, and raw responses
- Add an auditable cascade backend with injectable per-response policy, uncertainty/error fallback to chat, and per-metric escalation statistics in report summaries and CSV/JSON exports
- Add an offline-testable three-backend calibration harness and TypeSafe judge guide
- Support all judge backends in Minitest assertions and RSpec matchers, including chat fallback for custom metrics
- Preserve custom instructions and complete source context in TypeSafe metric questions
- Report token usage by provider and model, including calls made by custom metrics; exclude skipped evaluations from fallback rates
- Honor TypeSafe retry headers, apply configured timeouts to request writes, and accept structured Noul criteria
- Support expected pass/fail judgments and per-metric score thresholds in the calibration example

### Changed

- Name the decision model setting `decision_model` and its environment variable `RUBRIC_DECISION_MODEL`
- Include typed judge evidence and cascade fallback reasons in Minitest and RSpec failure messages without dumping raw responses
- Escalate conflicting high correctness and contradiction judgments under the default cascade policy without changing direct System One scores
- Batch context precision by the existing item limit with global answer IDs, per-batch state, and complete score/usage aggregation
- Explain HTTP 413 size failures and document that item batching does not bound request tokens or shared state size
- Record provider-reported chat token usage in metric details so calibration totals include both System One and cascade fallback calls; unavailable usage remains unknown

## [0.6.0] - 2026-09-18

### Changed

- Support stable RubyLLM 2.x with the `~> 2.0` dependency requirement, replacing the exact release-candidate pin
- Retain the RubyLLM 2 migration behavior introduced in 0.6.0.rc1, including optional temperature and provider protocol configuration

## [0.6.0.rc1] - 2026-09-08

This prerelease targets RubyLLM `2.0.0.rc1` and supports RubyLLM 2 only. Applications that use RubyLLM 1.x should stay on RubricLLM `0.5.x`. Stable `0.6.0` waits for the final RubyLLM 2.0 release and the complete Ruby 3.4 and 4.0 test matrix.

### Changed

- Require the exact RubyLLM `2.0.0.rc1` prerelease while the compatibility release is under review; Ruby >= 3.4 remains supported
- Keep `max_tokens` and `RUBRIC_MAX_TOKENS` as the public RubricLLM setting while RubyLLM maps the limit to the selected provider and protocol
- Treat explicit `temperature: nil` as an instruction to omit temperature from the provider request. Before 0.6.0.rc1, it selected `RUBRIC_TEMPERATURE` or `0.0`; an omitted temperature still reads `RUBRIC_TEMPERATURE` and defaults to `0.0`
- Use OpenAI Responses by default through RubyLLM 2. OpenAI-compatible gateways that only accept Chat Completions can set `config.openai_protocol = :chat_completions`
- Keep RubyLLM transport retries and RubricLLM judge retries separate. With RubyLLM's default `config.max_retries = 3` and RubricLLM's default `max_retries: 2`, a retryable metric failure can produce up to `(3 + 1) * (2 + 1) = 12` HTTP attempts
- Keep Rails persistence migrations separate. Applications that use RubyLLM's Rails records must follow RubyLLM's upstream 2.0 migration guide

## [0.5.0] - 2026-08-23

### Fixed

- The RSpec `hallucinate` matcher no longer reports a hallucination when the judge returns no score. A failed judge call previously read as a positive match and failed the build with a false verdict
- `Comparison` pairs samples by `sample[:question]` instead of array position. Two reports built from the same dataset in a different order produced an invalid paired t-test. Questions present in only one report are dropped with a warning
- `Judge#call` retries only transient failures (`RubyLLM::RateLimitError`, `ServerError`, `ServiceUnavailableError`, `OverloadedError`). A bad API key, an exhausted quota, an over-long prompt, or a judge contract violation now fails on the first attempt instead of sleeping through the full retry schedule. Transport timeouts and connection resets are left to RubyLLM's connection, which already retries them
- `ContextPrecision` and `ContextRecall` drop blank and whitespace-only context chunks and return a `No context provided` error when nothing usable remains, matching `Faithfulness`
- `Statistics.two_tailed_p` rescues only `Math::DomainError`, `ZeroDivisionError`, and `FloatDomainError`. It previously swallowed every `StandardError` and returned 1.0
- A paired t-test over a constant difference returns 1.0 instead of a spurious near-zero p-value caused by float error in the variance
- The RSpec `hallucinate` matcher renders a missing score as `nil` in its failure message instead of an empty string

### Removed

- The `Comparison` constructor no longer warns about reports of different sizes. Different sizes are fine when the questions match, and equal sizes can still drop every pair when they do not. The pairing warnings report what is actually dropped

### Added

- Holm-Bonferroni correction across metrics in `Comparison`. Each result carries `:p_value_adjusted` next to the raw `:p_value`, `#summary` prints a `p-adj` column, and `#significant_improvements` / `#significant_regressions` test the adjusted value. Six independent tests at alpha 0.05 gave a family-wise false-positive rate near 26%
- `RubricLLM::Statistics`, a module holding the paired t-test, the two-tailed p-value, the Holm adjustment, and the incomplete beta function. No LLM calls, no state
- `Metrics::Base.normalize_context`, the single definition of usable context

### Changed

- The Minitest `assert_faithful` and `refute_hallucination` helpers and the RSpec `be_faithful` and `hallucinate` matchers raise `ArgumentError` on an empty or blank context instead of returning a verdict that no judge produced

## [0.4.0] - 2026-07-11

### Added

- `RubricLLM.evaluate_batch` validates every sample upfront (must be a Hash with non-nil `:question` and `:answer`, string or symbol keys) and raises `ArgumentError` with the offending index before any LLM call, so sequential and concurrent modes fail identically and without API spend

### Changed

- Add `csv` as a runtime dependency; `csv` moved from a default gem to a bundled gem in Ruby 3.4, so consumers previously hit a `LoadError` on `Report#export_csv`
- Require `ruby_llm ~> 1.16`

## [0.3.0] - 2026-07-11

### Changed

- `Result#pass?` now returns `false` when any metric errored during evaluation (fail-closed for CI gating)
- `Report#worst` now ranks results with no valid scores as worst instead of best

### Added

- `Result#errors` and `Result#valid?` expose per-metric judge failures
- `Result#to_h` and report JSON exports include metric error information
- Report summaries show a metric error count line when evaluation errors occurred

## [0.2.0] - 2026-07-11

### Changed

- Enforce schema-backed judge responses through RubyLLM structured output when supported
- Raise `RubricLLM::JudgeError` for empty, malformed, missing-score, non-numeric, or out-of-range judge responses instead of returning `nil` or clamping invalid scores
- Require `ruby_llm ~> 1.13` for named schema payload support in structured output
- Record judge failures per metric in `RubricLLM.evaluate` and `RubricLLM.evaluate_batch` as a `nil` score with the error message in details and continue the run, while non-judge errors propagate
- Remove dead score clamping and nil-response guards from LLM metrics now that the judge validates the response contract

## [0.1.2] - 2026-04-30

### Added

- Add standalone LLM-as-Judge examples for RAG scoring, batch reports, model comparison, custom metrics, and Minitest assertions

## [0.1.1] - 2026-03-24

### Fixed

- Use RubyLLM system instructions instead of the attachment API when calling the judge
- Roll back invalid global configuration changes when `RubricLLM.configure` validation fails
- Accept string-keyed batch dataset hashes in sequential and concurrent evaluation
- Stabilize Student's t-test p-value calculation for small deltas and ordinary sample sizes

## [0.1.0] - 2026-03-24

### Added

- LLM-as-Judge evaluation via RubyLLM (provider-agnostic)
- Built-in metrics: Faithfulness, Relevance, Correctness, ContextPrecision, ContextRecall, FactualAccuracy
- Pluggable metric interface (`RubricLLM::Metrics::Base`)
- Single-sample evaluation (`RubricLLM.evaluate`)
- Batch evaluation with reports (`RubricLLM.evaluate_batch`)
- A/B model comparison with paired t-tests (`RubricLLM.compare`)
- Retrieval metrics without LLM calls (`RubricLLM.evaluate_retrieval`)
- Minitest assertions (`RubricLLM::Assertions`)
- RSpec matchers (`RubricLLM::RSpecMatchers`)
- CSV and JSON export for reports
