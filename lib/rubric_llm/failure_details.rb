# frozen_string_literal: true

module RubricLLM
  module FailureDetails
    FIELDS = %i[backend model confidence probability probabilities contradiction_probability
                escalated escalation_reason error fallback_error].freeze
    MAX_ITEMS = 6
    MAX_TEXT = 240

    module_function

    def format(details)
      return "" unless details.is_a?(Hash)

      parts = [chat_details(details), diagnostics(details)]
      nested = details[:system_one]
      nested_details = diagnostics(nested) if nested.is_a?(Hash)
      parts << "System One attempt: #{nested_details}" if nested_details && !nested_details.empty?
      parts.compact.reject(&:empty?).map { |part| " #{part}" }.join
    end

    def chat_details(details)
      claims = details[:claims]
      unsupported = claims.select { |claim| claim.is_a?(Hash) && claim["supported"] == false } if claims.is_a?(Array)
      return "Claims not supported: #{unsupported.map { |claim| claim["claim"] }}" if unsupported&.any?

      details[:reasoning].to_s
    end

    def diagnostics(details)
      FIELDS.filter_map do |field|
        value = details[field]
        "#{field}=#{display(value)}" unless value.nil?
      end.join(", ")
    end

    def display(value)
      text = case value
             when Array
               limited(value, value.first(MAX_ITEMS).inspect)
             when Hash
               limited(value, value.first(MAX_ITEMS).to_h.inspect)
             else
               value.to_s
             end
      text.length > MAX_TEXT ? "#{text[0, MAX_TEXT]}..." : text
    end

    def limited(collection, text)
      collection.size > MAX_ITEMS ? "#{text} (+#{collection.size - MAX_ITEMS} more)" : text
    end
  end
end
