# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
