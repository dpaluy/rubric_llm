# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rubric_llm"
require "minitest/autorun"

# Stub for RubyLLM chat that returns predictable JSON responses.
module RubyLLMStub
  class FakeResponse
    attr_reader :content

    def initialize(content)
      @content = content
    end
  end

  class FakeChat
    attr_accessor :response_content
    attr_reader :last_system_prompt, :last_user_prompt, :last_params, :call_count

    def initialize(response_content: '{"score": 0.9, "reasoning": "test"}', fail_times: 0, error_class: RuntimeError)
      @response_content = response_content
      @fail_times = fail_times
      @error_class = error_class
      @call_count = 0
    end

    def with_temperature(_temp)
      self
    end

    def ask(prompt, with: nil, **)
      @call_count += 1
      @last_user_prompt = prompt
      @last_system_prompt = with
      raise @error_class, "transient failure" if @call_count <= @fail_times

      FakeResponse.new(response_content)
    end

    def with_params(**params)
      @last_params = params
      self
    end
  end

  def self.chat(**)
    @fake_chat || FakeChat.new
  end

  def self.fake_chat=(chat)
    @fake_chat = chat
  end

  def self.reset!
    @fake_chat = nil
  end
end

# Replace RubyLLM with our stub for all tests
Object.send(:remove_const, :RubyLLM) if defined?(RubyLLM) && RubyLLM != RubyLLMStub
RubyLLM = RubyLLMStub

module TestSetup
  def setup
    RubyLLMStub.reset!
    RubricLLM.reset_configuration!
  end

  def teardown
    RubyLLMStub.reset!
    RubricLLM.reset_configuration!
  end

  def stub_judge_response(json_string)
    chat = RubyLLMStub::FakeChat.new(response_content: json_string)
    RubyLLMStub.fake_chat = chat
  end
end
