# frozen_string_literal: true

require "test_helper"

class TestJudgmentThreshold < Minitest::Test
  include TestSetup

  def test_judgment_threshold_defaults_to_half
    assert_in_delta 0.5, RubricLLM::Config.new.judgment_threshold
  end

  def test_judgment_threshold_reads_env
    previous = ENV.fetch("RUBRIC_JUDGMENT_THRESHOLD", nil)
    ENV["RUBRIC_JUDGMENT_THRESHOLD"] = "0.3"

    assert_in_delta 0.3, RubricLLM::Config.new.judgment_threshold
  ensure
    previous.nil? ? ENV.delete("RUBRIC_JUDGMENT_THRESHOLD") : ENV["RUBRIC_JUDGMENT_THRESHOLD"] = previous
  end

  def test_judgment_threshold_survives_to_h
    config = RubricLLM::Config.new(judgment_threshold: 0.35)

    assert_in_delta 0.35, RubricLLM::Config.new(**config.to_h).judgment_threshold
  end

  def test_validate_rejects_out_of_range_judgment_threshold
    error = assert_raises(RubricLLM::ConfigurationError) { RubricLLM::Config.new(judgment_threshold: 1.5).validate! }

    assert_includes error.message, "judgment_threshold"
  end
end
