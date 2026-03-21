# frozen_string_literal: true

module RubricLLM
  class RetrievalResult
    attr_reader :retrieved, :relevant

    def initialize(retrieved:, relevant:)
      @retrieved = Array(retrieved)
      @relevant = Set.new(Array(relevant))
    end

    def precision_at_k(k)
      top_k = retrieved.first(k)
      return 0.0 if top_k.empty?

      hits = top_k.count { |doc| relevant.include?(doc) }
      hits / top_k.size.to_f
    end

    def recall_at_k(k)
      return 0.0 if relevant.empty?

      top_k = retrieved.first(k)
      hits = top_k.count { |doc| relevant.include?(doc) }
      hits / relevant.size.to_f
    end

    # Mean Reciprocal Rank — reciprocal of the rank of the first relevant document.
    def mrr
      retrieved.each_with_index do |doc, i|
        return 1.0 / (i + 1) if relevant.include?(doc)
      end
      0.0
    end

    # Normalized Discounted Cumulative Gain.
    def ndcg(k: retrieved.size)
      return 0.0 if relevant.empty?

      dcg = retrieved.first(k).each_with_index.sum do |doc, i|
        gain = relevant.include?(doc) ? 1.0 : 0.0
        gain / Math.log2(i + 2)
      end

      ideal_count = [relevant.size, k].min
      idcg = (0...ideal_count).sum { |i| 1.0 / Math.log2(i + 2) }

      return 0.0 if idcg.zero?

      dcg / idcg
    end

    def hit_rate
      retrieved.any? { |doc| relevant.include?(doc) } ? 1.0 : 0.0
    end

    def to_h
      k = retrieved.size
      {
        precision_at_k: precision_at_k(k),
        recall_at_k: recall_at_k(k),
        mrr: mrr,
        ndcg: ndcg,
        hit_rate: hit_rate
      }
    end
  end
end
