# frozen_string_literal: true

module RubricLLM
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class JudgeError < Error; end
end
