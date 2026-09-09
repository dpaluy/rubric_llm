# frozen_string_literal: true

require_relative "helper"

class IsolationContract < RealClientContract
  def test_unmatched_requests_fail_without_network
    error = assert_raises(RubricLLM::JudgeError) { judge_call(max_retries: 2) }

    assert_includes error.message, "no stubbed request"
    assert_equal 1, @connections.size
  end

  def test_fixture_settings_restore_after_success
    verify_restoration(fail_verification: false)
  end

  def test_fixture_settings_restore_even_when_fixture_verification_fails
    verify_restoration(fail_verification: true)
  end

  private

  def verify_restoration(fail_verification:)
    saved = @saved_settings.keys.to_h { |key| [key, RubyLLM.config.public_send(key)] }
    registry = RubyLLM::Models.instance_variable_get(:@instance)
    fixture = RealClientContract.new("fixture")
    fixture.setup
    fixture.stub_response
    if fail_verification
      RubyLLM.config.openai_protocol = :chat_completions
      RubyLLM.config.max_retries = 7
      error = assert_raises(RuntimeError) { fixture.teardown }

      assert_includes error.message, "Expected post /v1/responses"
    else
      assert_in_delta(0.9, fixture.judge_call.fetch("score"))
      fixture.teardown
    end

    assert_equal(saved, saved.keys.to_h { |key| [key, RubyLLM.config.public_send(key)] })
    assert_same registry, RubyLLM::Models.instance_variable_get(:@instance)
  end
end
