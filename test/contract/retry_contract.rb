# frozen_string_literal: true

require_relative "helper"

class RetryContract < RealClientContract
  [429, 500, 503, 529].each do |status|
    define_method("test_http_#{status}_recovers_within_transport_retry") do
      RubyLLM.config.max_retries = 1
      stub_response(status:, error: "temporary fixture failure")
      stub_response

      assert_in_delta(0.9, judge_call(max_retries: 2).fetch("score"))
      assert_equal 2, @requests.size
      assert_equal 1, @connections.size
    end

    define_method("test_http_#{status}_recovers_on_outer_retry") do
      RubyLLM.config.max_retries = 1
      2.times { stub_response(status:, error: "temporary fixture failure") }
      stub_response

      assert_in_delta(0.9, judge_call(max_retries: 2).fetch("score"))
      assert_equal 3, @requests.size
      assert_equal 2, @connections.size
    end

    define_method("test_http_#{status}_exhausts_both_retry_budgets") do
      RubyLLM.config.max_retries = 1
      stub_response(status:, error: "temporary fixture failure")
      error = assert_raises(RubricLLM::JudgeError) { judge_call(max_retries: 2) }

      assert_includes error.message, "temporary fixture failure"
      assert_equal 6, @requests.size
      assert_equal 3, @connections.size
    end
  end

  {
    bad_request: [400, "invalid parameter"],
    unauthorized: [401, "invalid fixture key"],
    payment_quota: [402, "quota exhausted"],
    context_length: [400, "maximum context length exceeded"],
    throttled_context_length: [429, "maximum context length exceeded"]
  }.each do |name, (status, message)|
    define_method("test_#{name}_does_not_retry") do
      RubyLLM.config.max_retries = 2
      stub_response(status:, error: message)
      error = assert_raises(RubricLLM::JudgeError) { judge_call(max_retries: 2) }

      assert_includes error.message, message
      assert_equal 1, @requests.size
      assert_equal 1, @connections.size
    end
  end

  # The RC classifies OpenAI's HTTP 429 quota response as RateLimitError.
  # Preserve this existing retry behavior, including the bounded attempt count.
  def test_429_insufficient_quota_retains_upstream_retry_classification
    RubyLLM.config.max_retries = 1
    @stubs.post("https://openai.invalid/v1/responses") do |env|
      @requests << JSON.parse(env.body)
      [429, { "Content-Type" => "application/json" }, JSON.generate(
        error: { message: "You exceeded your current quota", type: "insufficient_quota", code: "insufficient_quota" }
      )]
    end
    error = assert_raises(RubricLLM::JudgeError) { judge_call(max_retries: 2) }

    assert_includes error.message, "You exceeded your current quota"
    assert_equal 6, @requests.size
    assert_equal 3, @connections.size
  end

  [Faraday::TimeoutError, Faraday::ConnectionFailed].each do |error_class|
    define_method("test_#{error_class.name.split("::").last}_stops_after_transport_retries") do
      RubyLLM.config.max_retries = 2
      stub_response { raise error_class, "offline transport failure" }
      error = assert_raises(RubricLLM::JudgeError) { judge_call(max_retries: 2) }

      assert_includes error.message, "offline transport failure"
      assert_equal 3, @requests.size
      assert_equal 1, @connections.size
    end
  end
end
