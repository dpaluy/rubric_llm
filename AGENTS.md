# Repository Guidelines

## Project Structure & Module Organization

RubricLLM is a Ruby gem. Runtime code lives in `lib/rubric_llm/`, with the public entrypoint at `lib/rubric_llm.rb`. Metric implementations are in `lib/rubric_llm/metrics/`. Minitest helpers live in `lib/rubric_llm/minitest.rb`. Tests live under `test/`, with metric tests in `test/metrics/`. Project metadata is in `rubric_llm.gemspec`, `Gemfile`, and `Rakefile`.

## Build, Test, and Development Commands

- `bundle install` installs gem dependencies.
- `bundle exec rake test` runs the Minitest suite.
- `bundle exec rubocop` runs static style checks using `.rubocop.yml`.
- `bundle exec rake` runs the default gate: tests plus RuboCop.

## Coding Style & Naming Conventions

Use Ruby 3.4+ syntax and keep files `# frozen_string_literal: true`. Follow the `RubricLLM` namespace. Use snake_case filenames and method names. Keep metric classes small and focused under `RubricLLM::Metrics`. RuboCop enforces double-quoted strings, 140-character lines, and Minitest rules.

## Testing Guidelines

Tests use Minitest only. Name files `test/test_*.rb` or `test/metrics/test_*.rb`. Put shared setup in `test/test_helper.rb`. Stub LLM behavior through `RubyLLMStub`; tests must not make network calls. Add regression tests when touching judge parsing, retry/error handling, score aggregation, metric math, or Minitest assertions.

## Commit & Pull Request Guidelines

Recent history uses Conventional Commits, for example `feat: initialize rubric_llm gem` and `fix(core): harden judge evaluation regressions`. Keep subjects short, imperative, and scoped when useful. Pull requests should state behavior changes, public API impact, and verification commands run.

## Security & Configuration Tips

Do not commit provider API keys, recorded prompts containing secrets, or generated `.gem` files. Keep tests deterministic and offline.
