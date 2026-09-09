# frozen_string_literal: true

require "minitest/autorun"
require "rubric_llm"
require "faraday/adapter/test"
require_relative "response_fixtures"

# This suite runs in its own process. Never require the unit test helper here.
class RealClientContract < Minitest::Test
  include ResponseFixtures

  SETTINGS = {
    openai_api_key: "offline-openai", anthropic_api_key: "offline-anthropic", gemini_api_key: "offline-gemini",
    openai_api_base: "https://openai.invalid/v1", anthropic_api_base: "https://anthropic.invalid",
    gemini_api_base: "https://gemini.invalid/v1beta", openai_protocol: nil, gemini_protocol: nil,
    max_retries: 0, retry_interval: 0, retry_interval_randomness: 0, http_proxy: nil
  }.freeze

  def setup
    super
    @saved_settings = (SETTINGS.keys + [:faraday_adapter]).to_h { |key| [key, RubyLLM.config.public_send(key)] }
    @saved_registry = RubyLLM::Models.instance_variable_get(:@instance)
    @stubs = Faraday::Adapter::Test::Stubs.new
    @requests = []
    @connections = []
    install_adapter
    SETTINGS.each { |key, value| RubyLLM.config.public_send("#{key}=", value) }
    RubyLLM::Models.instance_variable_set(:@instance, RubyLLM::Models.new(fixture_models))
  end

  def teardown
    @stubs&.verify_stubbed_calls
  ensure
    @saved_settings&.each { |key, value| RubyLLM.config.public_send("#{key}=", value) }
    RubyLLM::Models.instance_variable_set(:@instance, @saved_registry)
    super
  end

  def configuration(**)
    RubricLLM::Config.new(judge_model: "gpt-4o", judge_provider: :openai, temperature: 0.0, max_tokens: 256,
                          max_retries: 0, retry_base_delay: 0, concurrency: 1, **)
  end

  def judge_call(**)
    RubricLLM::Judge.new(config: configuration(**)).call(system_prompt: "Judge the answer", user_prompt: "Test answer")
  end

  def stub_response(path: "https://openai.invalid/v1/responses", **)
    @stubs.post(path) do |env|
      @requests << JSON.parse(env.body)
      yield(env) if block_given?
      response_fixture(**)
    end
  end

  private

  def install_adapter
    stubs = @stubs
    connections = @connections
    RubyLLM.config.faraday_adapter = Class.new(Faraday::Adapter::Test) do
      define_method(:initialize) do |app|
        connections << self
        super(app, stubs)
      end
    end
  end

  def fixture_models
    [["gpt-4o", "openai"], ["claude-sonnet-4", "anthropic"], ["gemini-2.5-flash", "gemini"],
     ["offline-text", "openai"]].map do |id, provider|
      RubyLLM::Model.new(id:, provider:, name: id, max_output_tokens: 8192,
                         modalities: { input: ["text"], output: ["text"] },
                         capabilities: id == "offline-text" ? [] : ["structured_output"])
    end
  end
end
