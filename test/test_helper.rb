# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "json"
require "rubric_llm"
require "ruby_llm/chat"
require "minitest/autorun"

# Stub for RubyLLM chat that returns predictable JSON responses.
module RubyLLMStub
  class FakeModel
    attr_reader :capabilities

    def initialize(capabilities: ["structured_output"])
      @capabilities = capabilities.map(&:to_s)
    end

    def supports?(capability)
      capabilities.include?(capability.to_s)
    end
  end

  class FakeResponse
    attr_reader :content, :tokens

    def initialize(content, tokens: nil)
      @content = content
      @tokens = tokens
    end
  end

  class FakeChat
    attr_accessor :response_content
    attr_reader :last_system_prompt, :last_user_prompt, :last_attachments, :last_schema,
                :last_temperature, :last_max_output_tokens, :call_count, :model

    def initialize(response_content: '{"score": 0.9, "reasoning": "test"}', fail_times: 0, error_class: RuntimeError,
                   model: nil, response_tokens: nil)
      @response_content = response_content
      @fail_times = fail_times
      @error_class = error_class
      @model = model || FakeModel.new
      @response_tokens = response_tokens
      @call_count = 0
    end

    def with_temperature(temperature)
      @last_temperature = temperature
      self
    end

    def with_instructions(instructions, append: false, cache_until_here: false)
      @cache_until_here = cache_until_here
      @last_system_prompt =
        if append && @last_system_prompt
          "#{@last_system_prompt}\n#{instructions}"
        else
          instructions
        end
      self
    end

    def ask(message = nil, with: nil, &)
      @call_count += 1
      @last_user_prompt = message
      @last_attachments = with

      Array(with).compact.each do |attachment|
        next unless attachment.is_a?(String)
        next if File.exist?(attachment)

        raise Errno::ENOENT, attachment
      end

      raise @error_class, "transient failure" if @call_count <= @fail_times

      FakeResponse.new(response_content, tokens: @response_tokens)
    end

    def with_max_output_tokens(max_output_tokens)
      @last_max_output_tokens = max_output_tokens
      self
    end

    def with_schema(schema)
      @last_schema = schema
      self
    end
  end

  def self.chat(*, **, &)
    @fake_chat || FakeChat.new
  end

  def self.fake_chat=(chat)
    @fake_chat = chat
  end

  def self.reset!
    @fake_chat = nil
  end
end

# Keep handles on real RubyLLM types before replacing its top-level constant.
RubyLLMTokens = RubyLLM::Tokens
RubyLLMReal = RubyLLM if defined?(RubyLLM) && RubyLLM != RubyLLMStub

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
