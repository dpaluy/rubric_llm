# frozen_string_literal: true

require "test_helper"

class TestSystemOneClientUsage < Minitest::Test
  FakeHTTPResponse = Struct.new(:code, :body, :headers) do
    def [](name)
      headers&.find { |key, _value| key.to_s.casecmp?(name) }&.last
    end
  end

  class SequenceTransport
    attr_reader :calls

    def initialize(*outcomes)
      @outcomes = outcomes
      @calls = 0
    end

    def call(**)
      @calls += 1
      outcome = @outcomes.fetch(@calls - 1)
      raise outcome if outcome.is_a?(Exception)

      outcome
    end
  end

  class Sleeper
    attr_reader :delays

    def initialize
      @delays = []
    end

    def sleep(delay)
      @delays << delay
    end
  end

  def setup
    super
    @config = RubricLLM::Config.new(
      typesafe_api_key: "offline", typesafe_model: "requested-model", max_retries: 2, retry_base_delay: 0
    )
    @question = RubricLLM::SystemOne::Question.noul("urgent", instructions: "Is it urgent?")
  end

  def test_timeout_then_success_records_unknown_and_paid_usage
    transport = SequenceTransport.new(Net::ReadTimeout.new("timed out"), response(200, noul_body))
    client = build_client(transport)

    client.call(state: "x", questions: [@question])

    assert_equal [unknown_attempt, success_attempt], client.usage_attempts
    assert_equal 2, transport.calls
  end

  def test_429_then_success_records_unknown_and_paid_usage
    transport = SequenceTransport.new(response(429, "busy"), response(200, noul_body))
    client = build_client(transport)

    client.call(state: "x", questions: [@question])

    assert_equal [unknown_attempt, success_attempt], client.usage_attempts
    assert_equal 2, transport.calls
  end

  def test_exhausted_timeouts_record_one_unknown_entry_per_call
    timeout = Net::ReadTimeout.new("timed out")
    transport = SequenceTransport.new(timeout, timeout, timeout)
    client = build_client(transport)

    assert_raises(RubricLLM::JudgeError) { client.call(state: "x", questions: [@question]) }

    assert_equal Array.new(3, unknown_attempt), client.usage_attempts
    assert_equal 3, transport.calls
  end

  def test_malformed_success_response_records_unknown_usage
    client = build_client(SequenceTransport.new(response(200, "not JSON")))

    assert_raises(RubricLLM::JudgeError) { client.call(state: "x", questions: [@question]) }

    assert_equal [unknown_attempt], client.usage_attempts
  end

  def test_invalid_success_usage_records_requested_model_and_unknown_usage
    body = JSON.generate(
      model: "jev-1.13.0", answers: { urgent: { type: "noul", noul: 0.92 } },
      usage: { input_tokens: "10", output_tokens: 2 }
    )
    client = build_client(SequenceTransport.new(response(200, body)))

    assert_raises(RubricLLM::JudgeError) { client.call(state: "x", questions: [@question]) }

    assert_equal [unknown_attempt], client.usage_attempts
  end

  def test_paid_usage_is_recorded_before_answer_validation
    body = JSON.generate(
      model: "jev-1.13.0", answers: { urgent: { type: "noul", noul: 1.4 } },
      usage: { input_tokens: 10, output_tokens: 2 }
    )
    client = build_client(SequenceTransport.new(response(200, body)))

    assert_raises(RubricLLM::JudgeError) { client.call(state: "x", questions: [@question]) }

    assert_equal [success_attempt], client.usage_attempts
  end

  private

  def build_client(transport)
    RubricLLM::SystemOne::Client.new(config: @config, transport:, sleeper: Sleeper.new)
  end

  def response(code, body)
    FakeHTTPResponse.new(code.to_s, body, {})
  end

  def noul_body
    JSON.generate(
      model: "jev-1.13.0", answers: { urgent: { type: "noul", noul: 0.92 } },
      usage: { input_tokens: 10, output_tokens: 2 }
    )
  end

  def unknown_attempt
    { backend: :system_one, provider: :typesafe, model: "requested-model", usage: nil }
  end

  def success_attempt
    { backend: :system_one, provider: :typesafe, model: "jev-1.13.0", usage: { "input_tokens" => 10, "output_tokens" => 2 } }
  end
end
