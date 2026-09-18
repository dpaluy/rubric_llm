# frozen_string_literal: true

require "test_helper"

class TestSystemOneClient < Minitest::Test # rubocop:disable Metrics/ClassLength
  FakeHTTPResponse = Struct.new(:code, :body)

  class SequenceTransport
    attr_reader :calls, :requests

    def initialize(*outcomes)
      @outcomes = outcomes
      @calls = 0
      @requests = []
    end

    def call(**kwargs)
      @calls += 1
      @requests << kwargs
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
    @config = RubricLLM::Config.new(typesafe_api_key: "secret-key", max_retries: 2, retry_base_delay: 0.25)
    @questions = [
      RubricLLM::SystemOne::Question.noul("urgent", instructions: "Is it urgent?"),
      RubricLLM::SystemOne::Question.choice("team", instructions: "Which team?", criteria: { billing: nil, technical: nil }),
      RubricLLM::SystemOne::Question.score("quality", instructions: "How good?", levels: %w[bad okay good])
    ]
  end

  def test_success_parses_all_primitives_and_preserves_raw_response
    raw = success_body
    transport = SequenceTransport.new(response(200, raw))
    result = client(transport:).call(state: { message: "Help" }, questions: @questions)

    assert_equal "jev-1.13.0", result.model
    assert_equal({ "input_tokens" => 12, "output_tokens" => 3 }, result.usage)
    assert_operator result.latency_ms, :>=, 0
    assert_in_delta 0.92, result.answers["urgent"].probability
    assert_equal "technical", result.answers["team"].choice
    assert_equal({ "billing" => 0.1, "technical" => 0.9 }, result.answers["team"].probabilities)
    assert_in_delta 0.65, result.answers["team"].confidence
    assert_in_delta 1.6, result.answers["quality"].score
    assert_in_delta 0.8, result.answers["quality"].normalized
    assert_same result.raw["answers"]["quality"], result.answers["quality"].raw

    sent = JSON.parse(transport.requests.first.fetch(:request).body)

    assert_equal "Bearer secret-key", transport.requests.first.fetch(:request)["Authorization"]
    assert_equal "jev-latest", sent["model"]
    assert_equal %w[quality team urgent], sent["questions"].keys.sort
    assert_equal({ "message" => "Help" }, sent["state"])
  end

  def test_noul_and_choice_normalization
    result = client(transport: SequenceTransport.new(response(200, success_body))).call(state: "Help", questions: @questions)

    assert_in_delta 0.08, result.answers["urgent"].normalized(invert: true)
    assert_in_delta 0.75, result.answers["team"].normalized(mapping: { technical: 0.75, billing: 0.0 })
  end

  def test_score_normalizes_three_and_five_levels
    three = @questions.last
    five = RubricLLM::SystemOne::Question.score("five", instructions: "Rate", levels: %w[a b c d e])
    raw = JSON.parse(success_body)
    raw["answers"] = {
      "quality" => raw["answers"]["quality"],
      "five" => score_answer(3.0, %w[a b c d e], [0.0, 0.0, 0.0, 1.0, 0.0])
    }
    result = client(transport: SequenceTransport.new(response(200, JSON.generate(raw)))).call(state: "x", questions: [three, five])

    assert_in_delta 0.8, result.answers["quality"].normalized
    assert_in_delta 0.75, result.answers["five"].normalized
  end

  def test_401_is_not_retried_and_body_is_redacted
    transport = SequenceTransport.new(response(401, '{"detail":"secret-key invalid"}'))

    error = assert_raises(RubricLLM::JudgeError) { client(transport:).call(state: "x", questions: [@questions.first]) }

    assert_equal 1, transport.calls
    assert_match(/HTTP 401/, error.message)
    assert_includes error.message, "[REDACTED]"
    refute_includes error.message, "secret-key"
  end

  def test_429_and_500_are_retried_with_exponential_backoff
    sleeper = Sleeper.new
    transport = SequenceTransport.new(response(429, "busy"), response(500, "down"), response(200, noul_body))

    result = client(transport:, sleeper:).call(state: "x", questions: [@questions.first])

    assert_in_delta 0.92, result.answers["urgent"].probability
    assert_equal [0.25, 0.5], sleeper.delays
    assert_equal 3, transport.calls
  end

  def test_timeout_is_retried_then_wrapped_without_key
    sleeper = Sleeper.new
    timeout = Net::ReadTimeout.new("secret-key timed out")
    transport = SequenceTransport.new(timeout, timeout, timeout)

    error = assert_raises(RubricLLM::JudgeError) do
      client(transport:, sleeper:).call(state: "x", questions: [@questions.first])
    end

    assert_equal 3, transport.calls
    assert_equal [0.25, 0.5], sleeper.delays
    refute_includes error.message, "secret-key"
    refute_includes error.full_message, "secret-key"
    assert_nil error.cause
  end

  def test_malformed_json_is_rejected_without_leaking_key_through_cause
    error = assert_raises(RubricLLM::JudgeError) do
      client(transport: SequenceTransport.new(response(200, "secret-key is not json"))).call(state: "x", questions: [@questions.first])
    end

    assert_match(/not valid JSON/, error.message)
    refute_includes error.full_message, "secret-key"
    assert_nil error.cause
  end

  def test_mismatched_question_ids_are_rejected
    parsed = JSON.parse(noul_body)
    parsed["answers"] = { "other" => parsed["answers"].fetch("urgent") }

    error = assert_raises(RubricLLM::JudgeError) do
      client(transport: SequenceTransport.new(response(200, JSON.generate(parsed)))).call(state: "x", questions: [@questions.first])
    end

    assert_match(/question ids do not match/, error.message)
  end

  def test_invalid_primitive_values_are_rejected
    parsed = JSON.parse(noul_body)
    parsed["answers"]["urgent"]["noul"] = 1.1

    error = assert_raises(RubricLLM::JudgeError) do
      client(transport: SequenceTransport.new(response(200, JSON.generate(parsed)))).call(state: "x", questions: [@questions.first])
    end

    assert_match(/noul must be finite/, error.message)
  end

  def test_invalid_probability_distribution_and_score_legend_are_rejected
    parsed = JSON.parse(success_body)
    parsed["answers"]["team"]["probabilities"] = { "billing" => 0.4, "technical" => 0.4 }
    assert_raises(RubricLLM::JudgeError) do
      client(transport: SequenceTransport.new(response(200, JSON.generate(parsed)))).call(state: "x", questions: @questions)
    end

    parsed = JSON.parse(success_body)
    parsed["answers"]["quality"]["legend"]["0"] = "wrong"
    assert_raises(RubricLLM::JudgeError) do
      client(transport: SequenceTransport.new(response(200, JSON.generate(parsed)))).call(state: "x", questions: @questions)
    end
  end

  def test_invalid_input_fails_before_transport
    transport = SequenceTransport.new
    duplicate = RubricLLM::SystemOne::Question.noul("urgent", instructions: "Again?")

    assert_raises(RubricLLM::ConfigurationError) do
      client(transport:).call(state: ["unsupported"], questions: [@questions.first])
    end
    assert_raises(RubricLLM::ConfigurationError) do
      client(transport:).call(state: "x", questions: [@questions.first, duplicate])
    end
    assert_raises(RubricLLM::ConfigurationError) do
      client(transport:).call(state: { invalid: Object.new }, questions: [@questions.first])
    end
    assert_raises(RubricLLM::ConfigurationError) do
      client(transport:).call(state: { invalid: Float::NAN }, questions: [@questions.first])
    end
    assert_equal 0, transport.calls
  end

  def test_non_string_models_fail_before_transport
    transport = SequenceTransport.new

    [123, { name: "jev-latest" }].each do |model|
      assert_raises(RubricLLM::ConfigurationError) do
        client(transport:).call(state: "x", questions: [@questions.first], model:)
      end
    end

    config = RubricLLM::Config.new(typesafe_api_key: "secret-key", typesafe_model: 123)
    assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Client.new(config:, transport:).call(state: "x", questions: [@questions.first])
    end
    assert_equal 0, transport.calls
  end

  def test_mutated_question_inputs_cannot_produce_invalid_requests
    levels = %w[bad good]
    question = RubricLLM::SystemOne::Question.score("quality", instructions: "Rate", levels:)
    levels.pop
    body = JSON.generate({
                           model: "jev-1.13.0",
                           answers: { quality: score_answer(1.0, %w[bad good], [0.0, 1.0]) },
                           usage: { input_tokens: 1, output_tokens: 1 }
                         })
    transport = SequenceTransport.new(response(200, body))

    client(transport:).call(state: "x", questions: [question])
    sent = JSON.parse(transport.requests.first.fetch(:request).body)

    assert_equal %w[bad good], sent.dig("questions", "quality", "criteria")
    assert_raises(FrozenError) { question.criteria.pop }
    assert_raises(FrozenError) { question.id.clear }
    assert_equal 1, transport.calls
  end

  def test_missing_api_key_fails_before_transport_even_with_chat_default
    transport = SequenceTransport.new
    config = RubricLLM::Config.new(typesafe_api_key: nil)

    error = assert_raises(RubricLLM::ConfigurationError) do
      RubricLLM::SystemOne::Client.new(config:, transport:).call(state: "x", questions: [@questions.first])
    end

    assert_match(/api_key is required/, error.message)
    assert_equal 0, transport.calls
  end

  def test_transport_error_redacts_api_key
    transport = SequenceTransport.new(RuntimeError.new("request with secret-key failed"))

    error = assert_raises(RubricLLM::JudgeError) { client(transport:).call(state: "x", questions: [@questions.first]) }

    assert_includes error.message, "[REDACTED]"
    refute_includes error.message, "secret-key"
    refute_includes error.full_message, "secret-key"
    assert_nil error.cause
  end

  private

  def client(transport:, sleeper: Sleeper.new)
    RubricLLM::SystemOne::Client.new(config: @config, transport:, sleeper:)
  end

  def response(code, body)
    FakeHTTPResponse.new(code.to_s, body)
  end

  def noul_body
    JSON.generate({
                    model: "jev-1.13.0",
                    answers: { urgent: { type: "noul", noul: 0.92 } },
                    usage: { input_tokens: 12, output_tokens: 3 }
                  })
  end

  def success_body
    JSON.generate({
                    model: "jev-1.13.0",
                    answers: {
                      urgent: { type: "noul", noul: 0.92 },
                      team: {
                        type: "choice", choice: "technical", probabilities: { billing: 0.1, technical: 0.9 }, confidence: 0.65
                      },
                      quality: score_answer(1.6, %w[bad okay good], [0.0, 0.4, 0.6])
                    },
                    usage: { input_tokens: 12, output_tokens: 3 }
                  })
  end

  def score_answer(score, levels, probabilities)
    {
      type: "score", score:, legend: levels.each_with_index.to_h { |level, index| [index.to_s, level] },
      probabilities: probabilities.each_with_index.to_h { |probability, index| [index.to_s, probability] }, confidence: 0.7
    }
  end
end
