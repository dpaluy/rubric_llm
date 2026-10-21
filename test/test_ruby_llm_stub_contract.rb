# frozen_string_literal: true

require "test_helper"

class TestRubyLLMStubContract < Minitest::Test
  CLIENT_METHODS = %i[
    ask
    model
    with_instructions
    with_temperature
    with_thinking
    with_max_output_tokens
    with_schema
  ].freeze

  TEST_ONLY_METHODS = %i[
    call_count
    last_attachments
    last_max_output_tokens
    last_schema
    last_system_prompt
    last_temperature
    last_thinking
    last_user_prompt
    response_content
    response_content=
  ].freeze

  def test_stub_chat_matches_preloaded_real_chat
    assert_empty contract_errors
  end

  def test_guard_detects_a_removed_client_method
    stub_class = Class.new(RubyLLMStub::FakeChat) do
      undef_method :with_schema
    end

    errors = contract_errors(stub_class:)

    assert_includes errors, "stub is missing client method with_schema"
  end

  def test_guard_detects_an_unsupported_keyword
    stub_class = Class.new(RubyLLMStub::FakeChat) do
      def with_instructions(instructions, append: false, replace: nil)
        @probe_arguments = [instructions, append, replace]
        self
      end
    end

    errors = contract_errors(stub_class:)

    assert_includes errors, "parameters differ for with_instructions"
  end

  def test_stub_module_methods_exist_on_real_ruby_llm
    %i[chat judge models].each do |method_name|
      assert_respond_to RubyLLMReal, method_name
    end
  end

  def test_stub_model_lookup_matches_real_registry
    stub_parameters = RubyLLMStub::FakeModels.instance_method(:find).parameters.map do |type, name|
      [type, name.to_s.delete_prefix("_").to_sym]
    end

    assert_equal RubyLLMReal::Models.instance_method(:find).parameters, stub_parameters
  end

  def test_stub_judgment_answers_match_real_readers
    { RubyLLMReal::Score => RubyLLMStub::FakeScore, RubyLLMReal::Probability => RubyLLMStub::FakeProbability }.each do |real, stub|
      real_readers = real.public_instance_methods(false) & %i[score levels probabilities confidence probability type]

      real_readers.each { |reader| assert stub.method_defined?(reader), "#{stub} is missing #{reader}" }
    end
  end

  private

  def contract_errors(stub_class: RubyLLMStub::FakeChat, real_class: RubyLLMReal::Chat)
    errors = []
    real_methods = real_class.public_instance_methods
    stub_methods = stub_class.public_instance_methods(false) - TEST_ONLY_METHODS

    CLIENT_METHODS.each do |method_name|
      if !stub_class.public_method_defined?(method_name)
        errors << "stub is missing client method #{method_name}"
      elsif !real_class.public_method_defined?(method_name)
        errors << "real client is missing client method #{method_name}"
      elsif stub_class.instance_method(method_name).parameters != real_class.instance_method(method_name).parameters
        errors << "parameters differ for #{method_name}"
      end
    end

    (stub_methods - CLIENT_METHODS).each do |method_name|
      errors << "stub has unknown client method #{method_name}" unless real_methods.include?(method_name)
    end

    errors
  end
end
