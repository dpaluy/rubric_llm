# frozen_string_literal: true

module RubricLLM
  class UsageSummary
    TOKEN_KEYS = %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens].freeze

    attr_reader :records

    def self.from_results(results)
      new(results.flat_map { |result| result.details.values.flat_map { |details| records_for(details) } })
    end

    def self.records_for(details)
      return [] unless details.is_a?(Hash)
      return details[:usage_attempts] if details.key?(:usage_attempts)

      records = []
      if details.key?(:usage)
        records << { backend: details[:backend], provider: details[:provider], model: details[:model], usage: details[:usage] }
      end
      records + records_for(details[:system_one])
    end

    def initialize(records)
      @records = records
    end

    def complete?
      records.any? && records.all? { |record| %i[input_tokens output_tokens].all? { |key| normalized(record).key?(key) } }
    end

    def total
      return nil unless complete?

      counts = records.map { |record| normalized(record) }
      counts.flat_map(&:keys).uniq.to_h { |key| [key, counts.sum { |usage| usage.fetch(key, 0) }] }
    end

    def by_model
      records.group_by { |record| record.values_at(:backend, :provider, :model) }.map do |identity, calls|
        backend, provider, model = identity
        summary = self.class.new(calls)
        { backend:, provider:, model:, calls: calls.length, usage: summary.total, usage_complete: summary.complete? }
      end
    end

    private

    def normalized(record)
      usage = record[:usage]
      return {} unless usage.is_a?(Hash)

      TOKEN_KEYS.each_with_object({}) do |key, tokens|
        value = usage[key] || usage[key.to_s]
        tokens[key] = value if value.is_a?(Numeric) && value.finite? && value >= 0
      end
    end
  end
end
