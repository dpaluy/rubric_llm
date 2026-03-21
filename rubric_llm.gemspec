# frozen_string_literal: true

require_relative "lib/rubric_llm/version"

Gem::Specification.new do |spec|
  spec.name = "rubric_llm"
  spec.version = RubricLLM::VERSION
  spec.authors = ["David Paluy"]
  spec.email = ["dpaluy@users.noreply.github.com"]

  spec.summary = "Lightweight LLM evaluation framework for Ruby"
  spec.description = "Provider-agnostic LLM evaluation with pluggable metrics, " \
                     "statistical A/B comparison, and test framework integration. " \
                     "Ragas for Ruby, powered by RubyLLM."
  spec.homepage = "https://github.com/dpaluy/rubric_llm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/rubric_llm"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[
                        test/ spec/ bin/ Gemfile .gitignore .github/ .rubocop.yml
                        docs/ .agents/ AGENTS.md CLAUDE.md Rakefile .yardopts
                        .ruby-version .tool-versions skills/
                      ])
    end
  end

  spec.require_paths = ["lib"]
  spec.extra_rdoc_files = Dir["README.md", "CHANGELOG.md", "LICENSE.txt"]

  spec.add_dependency "ruby_llm", "~> 1.0"
end
