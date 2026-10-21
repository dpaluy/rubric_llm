# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "json"
require "rubric_llm"
require "ruby_llm/chat"
# Autoload the real classes the stub contract compares against before RubyLLM is replaced.
[RubyLLM::Models, RubyLLM::Score, RubyLLM::Probability].each(&:name)
require "minitest/autorun"

# Stub for RubyLLM chat that returns predictable JSON responses.
module RubyLLMStub
  ModelNotFoundError = RubyLLM::ModelNotFoundError
  Provider = RubyLLM::Provider

  class FakeModel
    attr_reader :capabilities, :type

    def initialize(capabilities: ["structured_output"], type: :chat)
      @capabilities = capabilities.map(&:to_s)
      @type = type
    end

    def supports?(capability)
      capabilities.include?(capability.to_s)
    end
  end

  class FakeResponse
    attr_reader :content

    def initialize(content)
      @content = content
    end
  end

  class FakeChat
    attr_accessor :response_content
    attr_reader :last_system_prompt, :last_user_prompt, :last_attachments, :last_schema,
                :last_temperature, :last_max_output_tokens, :last_thinking, :call_count, :model

    def initialize(response_content: '{"score": 0.9, "reasoning": "test"}', fail_times: 0, error_class: RuntimeError,
                   model: nil)
      @response_content = response_content
      @fail_times = fail_times
      @error_class = error_class
      @model = model || FakeModel.new
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

      FakeResponse.new(response_content)
    end

    def with_max_output_tokens(max_output_tokens)
      @last_max_output_tokens = max_output_tokens
      self
    end

    # Match RubyLLM's public method signature for the stub contract check.
    def with_thinking(enabled = true, **options) # rubocop:disable Style/OptionalBooleanParameter
      @last_thinking = { enabled:, **options }
      self
    end

    def with_schema(schema)
      @last_schema = schema
      self
    end
  end

  FakeProbability = Struct.new(:probability, keyword_init: true) do
    def type = :probability
  end

  FakeScore = Struct.new(:score, :levels, :probabilities, :confidence, keyword_init: true) do
    def type = :score
  end

  class FakeJudgment
    attr_reader :answers

    def initialize(answers)
      @answers = answers.transform_keys(&:to_s)
    end

    def [](name)
      answers[name.to_s]
    end
  end

  # Answers RubyLLM.judge calls. Answers are keyed by question name; unknown
  # questions are left unanswered.
  class FakeJudge
    attr_reader :calls

    def initialize(answers: {}, fail_times: 0, error_class: RuntimeError)
      @answers = answers
      @fail_times = fail_times
      @error_class = error_class
      @calls = []
    end

    def call(input, questions:, **)
      @calls << { input:, questions:, ** }
      raise @error_class, "transient failure" if @calls.size <= @fail_times

      answers = @answers.transform_keys(&:to_s)
      FakeJudgment.new(answers.slice(*questions.keys.map(&:to_s)))
    end

    def last_call
      calls.last
    end
  end

  class FakeModels
    attr_accessor :model, :error

    def find(_model_id, provider: nil, config: nil) # rubocop:disable Lint/UnusedMethodArgument
      raise error if error

      model || FakeModel.new
    end
  end

  def self.chat(*, **, &)
    @fake_chat || FakeChat.new
  end

  def self.fake_chat=(chat)
    @fake_chat = chat
  end

  def self.judge(input = nil, **)
    raise "RubyLLMStub.fake_judge is not set" unless @fake_judge

    @fake_judge.call(input, **)
  end

  def self.fake_judge=(judge)
    @fake_judge = judge
  end

  def self.fake_judge
    @fake_judge
  end

  def self.models
    @models ||= FakeModels.new
  end

  def self.reset!
    @fake_chat = nil
    @fake_judge = nil
    @models = nil
  end
end

# Keep a handle on the real RubyLLM so tests can name its error classes.
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

  # Configure a judgment model (such as TypeSafe's Jev) that answers with +answers+.
  def stub_judgment(answers = {}, **)
    RubyLLMStub.models.model = RubyLLMStub::FakeModel.new(capabilities: ["judgment"], type: :judgment)
    RubyLLMStub.fake_judge = RubyLLMStub::FakeJudge.new(answers:, **)
  end

  def fake_score(score, levels: 3)
    RubyLLMStub::FakeScore.new(score:, levels: Array.new(levels) { |i| "level #{i}" },
                               probabilities: { score.round => 1.0 }, confidence: 0.8)
  end

  def fake_probability(probability)
    RubyLLMStub::FakeProbability.new(probability:)
  end
end
