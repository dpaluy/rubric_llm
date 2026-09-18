# frozen_string_literal: true

module RubricLLM
  module Text
    module_function

    # A deliberately small, deterministic sentence splitter. It keeps terminal
    # punctuation and treats text without terminal punctuation as one sentence.
    def sentences(text)
      text.to_s.scan(/.+?(?:[.!?]+[”’"')\]}]*(?=\s|\z)|\z)/m).map(&:strip).reject(&:empty?)
    end
  end
end
