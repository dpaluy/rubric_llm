# frozen_string_literal: true

require "test_helper"
require "rubric_llm/minitest"
require "rubric_llm/rspec"

class TestHelperBackends < Minitest::Test
  include TestSetup
  include RubricLLM::Assertions

  class OfflineClient
    attr_reader :calls

    def initialize(probability)
      @probability = probability
      @calls = 0
    end

    def call(questions:, **)
      @calls += 1
      answers = questions.to_h do |question|
        raw = { "type" => "noul", "noul" => @probability }
        [question.id, RubricLLM::SystemOne::Answer::Noul.new(raw)]
      end
      RubricLLM::SystemOne::Response.new(
        answers:, usage: { "input_tokens" => 1, "output_tokens" => 1 }, model: "offline", latency_ms: 0.0, raw: {}
      )
    end
  end

  def test_assertion_runs_each_configured_backend
    %i[chat system_one cascade].each do |backend|
      with_offline_providers(backend) do |config, client, chat|
        assert_faithful("Paris.", ["Paris is France's capital."], question: "What is France's capital?", config:)
        assert_equal backend == :chat ? 0 : 1, client.calls
        assert_equal backend == :chat ? 1 : 0, chat.call_count
      end
    end
  end

  def test_matcher_runs_each_configured_backend
    %i[chat system_one cascade].each do |backend|
      with_offline_providers(backend) do |config, client, chat|
        matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["Paris is France's capital."]).with_config(config)

        assert matcher.matches?("Paris.")
        assert_equal backend == :chat ? 0 : 1, client.calls
        assert_equal backend == :chat ? 1 : 0, chat.call_count
      end
    end
  end

  def test_assertion_and_matcher_escalate_uncertain_results
    with_offline_providers(:cascade, probability: 0.5) do |config, client, chat|
      assert_faithful("Paris.", ["Paris is France's capital."], config:)
      matcher = RubricLLM::RSpecMatchers::FaithfulnessMatcher.new(["Paris is France's capital."]).with_config(config)

      assert matcher.matches?("Paris.")
      assert matcher.result[:details][:escalated]
      assert_equal 2, client.calls
      assert_equal 2, chat.call_count
    end
  end

  private

  def with_offline_providers(backend, probability: 0.95)
    config = RubricLLM::Config.new(judge_backend: backend, typesafe_api_key: "offline")
    client = OfflineClient.new(probability)
    chat = RubyLLMStub::FakeChat.new
    RubyLLMStub.fake_chat = chat
    singleton = RubricLLM::SystemOne::Client.singleton_class
    singleton.define_method(:new) { |**| client }
    yield(config, client, chat)
  ensure
    singleton.remove_method(:new)
  end
end
