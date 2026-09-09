# frozen_string_literal: true

require_relative "helper"

class ProviderContract < RealClientContract
  def test_openai_responses_request_and_json_text_response
    stub_response

    assert_equal({ "score" => 0.9, "reasoning" => "offline" }, judge_call(custom_prompt: "Be precise"))

    payload = @requests.fetch(0)

    assert_equal "gpt-4o", payload["model"]
    assert_equal "Judge the answer\n\nAdditional instructions:\nBe precise", payload["instructions"]
    assert_equal 256, payload["max_output_tokens"]
    assert_in_delta(0.0, payload["temperature"])
    assert_equal "Test answer", payload.dig("input", 0, "content")
    assert_schema payload.dig("text", "format")
    assert_equal 1, @connections.size
  end

  def test_openai_responses_omits_explicit_nil_temperature
    stub_response
    judge_call(temperature: nil)

    refute @requests.fetch(0).key?("temperature")
  end

  def test_configured_chat_completions_maps_tokens_and_schema
    RubyLLM.config.openai_protocol = :chat_completions
    stub_response(path: "https://openai.invalid/v1/chat/completions", protocol: :chat_completions)

    assert_in_delta(0.9, judge_call(temperature: nil).fetch("score"))

    payload = @requests.fetch(0)

    assert_equal "gpt-4o", payload["model"]
    assert_equal 256, payload["max_completion_tokens"]
    refute payload.key?("max_tokens")
    refute payload.key?("temperature")
    assert_equal [{ "role" => "developer", "content" => "Judge the answer" },
                  { "role" => "user", "content" => "Test answer" }], payload["messages"]
    assert_equal "json_schema", payload.dig("response_format", "type")
    assert_schema payload.dig("response_format", "json_schema")
  end

  def test_chat_completions_preserves_numeric_temperature
    RubyLLM.config.openai_protocol = :chat_completions
    stub_response(path: "https://openai.invalid/v1/chat/completions", protocol: :chat_completions)
    judge_call(temperature: 0.7)

    assert_in_delta(0.7, @requests.fetch(0).fetch("temperature"))
  end

  def test_anthropic_request_and_validated_score
    stub_response(path: "https://anthropic.invalid/v1/messages", protocol: :anthropic)

    assert_in_delta(0.9, judge_call(judge_model: "claude-sonnet-4", judge_provider: :anthropic).fetch("score"))

    payload = @requests.fetch(0)

    assert_equal "claude-sonnet-4", payload["model"]
    assert_equal 256, payload["max_tokens"]
    assert_in_delta(0.0, payload["temperature"])
    assert_equal "Judge the answer", payload.dig("system", 0, "text")
    assert_equal "Test answer", payload.dig("messages", 0, "content", 0, "text")
    assert_equal "json_schema", payload.dig("output_config", "format", "type")
    assert_equal schema_body, payload.dig("output_config", "format", "schema")
  end

  def test_gemini_request_and_validated_score
    stub_response(path: "https://gemini.invalid/v1beta/models/gemini-2.5-flash:generateContent", protocol: :gemini)

    assert_in_delta(0.9, judge_call(judge_model: "gemini-2.5-flash", judge_provider: :gemini).fetch("score"))

    payload = @requests.fetch(0)

    assert_equal "Judge the answer", payload.dig("systemInstruction", "parts", 0, "text")
    assert_equal "Test answer", payload.dig("contents", 0, "parts", 0, "text")
    assert_equal 256, payload.dig("generationConfig", "maxOutputTokens")
    assert_in_delta(0.0, payload.dig("generationConfig", "temperature"))
    assert_equal "application/json", payload.dig("generationConfig", "responseMimeType")
    assert_equal schema_body, payload.dig("generationConfig", "responseJsonSchema")
  end

  private

  def assert_schema(schema)
    assert_equal "rubric_llm_metric_response", schema["name"]
    assert_same false, schema.fetch("strict")
    assert_equal schema_body, schema["schema"]
  end

  def schema_body
    JSON.parse(JSON.generate(RubricLLM::Judge::METRIC_RESPONSE_SCHEMA.fetch(:schema)))
  end
end
