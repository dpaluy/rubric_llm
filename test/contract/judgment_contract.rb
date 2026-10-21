# frozen_string_literal: true

require_relative "helper"

class JudgmentContract < RealClientContract
  SYSTEM_ONE_URL = "https://typesafe.invalid/v1/systemone"

  def test_jev_score_metric_request_and_response
    stub_system_one(
      "answers" => {
        "correctness" => { "score" => 1.5, "legend" => { "0" => "Wrong", "1" => "Partly", "2" => "Correct" },
                           "probabilities" => { "0" => 0.1, "1" => 0.3, "2" => 0.6 }, "confidence" => 0.8 }
      }
    ) do |env|
      assert_equal "Bearer offline-typesafe", env.request_headers["Authorization"]
    end

    result = metric(RubricLLM::Metrics::Correctness).call(question: "Capital?", answer: "Paris", ground_truth: "Paris")
    payload = @requests.fetch(0)

    assert_in_delta 0.75, result[:score]
    assert_equal({ 0 => 0.1, 1 => 0.3, 2 => 0.6 }, result[:details][:probabilities])
    assert_equal "jev-latest", payload["model"]
    assert_equal({ "question" => "Capital?", "answer" => "Paris", "ground_truth" => "Paris" }, payload["state"])
    assert_equal "score", payload.dig("questions", "correctness", "type")
    assert_equal RubricLLM::Metrics::Correctness::JUDGMENT_LEVELS, payload.dig("questions", "correctness", "criteria")
  end

  def test_jev_probability_questions_per_context
    stub_system_one("answers" => { "context_1" => { "noul" => 0.9 }, "context_2" => { "noul" => 0.1 } })

    result = metric(RubricLLM::Metrics::ContextPrecision).call(question: "Capital?", context: %w[Paris Bananas])
    questions = @requests.fetch(0)["questions"]

    assert_in_delta 0.5, result[:score]
    assert_equal %w[context_1 context_2], questions.keys
    assert_equal "noul", questions.dig("context_1", "type")
  end

  def test_jev_judgment_errors_become_judge_errors
    @stubs.post(SYSTEM_ONE_URL) { [401, { "Content-Type" => "application/json" }, '{"error":{"message":"bad key"}}'] }

    error = assert_raises(RubricLLM::JudgeError) do
      metric(RubricLLM::Metrics::Relevance).call(question: "q", answer: "a")
    end

    assert_includes error.message, "Judge call failed"
  end

  private

  def metric(klass)
    config = RubricLLM::Config.new(judge_model: "jev-latest", judge_provider: :typesafe, max_retries: 0, retry_base_delay: 0)
    klass.new(judge: RubricLLM::Judge.new(config:))
  end

  def stub_system_one(body)
    @stubs.post(SYSTEM_ONE_URL) do |env|
      @requests << JSON.parse(env.body)
      yield(env) if block_given?
      [200, { "Content-Type" => "application/json" },
       JSON.generate({ "model" => "jev-latest", "usage" => { "input_tokens" => 10, "output_tokens" => 1 } }.merge(body))]
    end
  end
end
