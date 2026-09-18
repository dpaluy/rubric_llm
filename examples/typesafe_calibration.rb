# frozen_string_literal: true

require "json"
require "rubric_llm"

module TypeSafeCalibration
  module_function

  def pearson(left, right)
    pairs = left.zip(right).reject { |a, b| a.nil? || b.nil? }
    return nil if pairs.length < 2

    xs, ys = pairs.transpose
    x_mean = xs.sum / xs.length.to_f
    y_mean = ys.sum / ys.length.to_f
    numerator = pairs.sum { |x, y| (x - x_mean) * (y - y_mean) }
    denominator = Math.sqrt(xs.sum { |x| (x - x_mean)**2 } * ys.sum { |y| (y - y_mean)**2 })
    denominator.zero? ? nil : numerator / denominator
  end

  def mad(left, right)
    pairs = left.zip(right).reject { |a, b| a.nil? || b.nil? }
    return nil if pairs.empty?

    pairs.sum { |a, b| (a - b).abs } / pairs.length.to_f
  end

  def run(dataset, config: RubricLLM.config, evaluator: RubricLLM.method(:evaluate_batch))
    reports = %i[chat system_one cascade].to_h do |backend|
      backend_config = RubricLLM::Config.new(**config.to_h, judge_backend: backend)
      [backend, evaluator.call(dataset, config: backend_config)]
    end

    reports.each do |backend, report|
      puts "\n#{backend}:"
      puts report.summary
      puts "tokens: #{report.total_usage || "unknown (provider did not report usage)"}"
      puts format("wall time: %.3fs", report.duration)
      escalations = report.escalation_stats.values
      escalated = escalations.sum { |value| value[:escalated] }
      total = escalations.sum { |value| value[:total] }
      puts "escalation rate: #{total.zero? ? "n/a" : format("%.1f%%", 100.0 * escalated / total)}"
    end

    [%i[chat system_one], %i[chat cascade], %i[system_one cascade]].each do |left, right|
      puts "\n#{left} vs #{right}"
      puts RubricLLM.compare(reports.fetch(left), reports.fetch(right)).summary
    end

    puts "\nAgreement: chat vs system_one"
    (reports[:chat].metric_stats.keys | reports[:system_one].metric_stats.keys).each do |metric|
      chat = reports[:chat].scores_for(metric)
      system_one = reports[:system_one].scores_for(metric)
      correlation = pearson(chat, system_one)
      difference = mad(chat, system_one)
      puts format("%-20s Pearson=%s MAD=%s", metric, display(correlation), display(difference))
    end
    reports
  end

  def display(value)
    value.nil? ? "n/a (missing or constant values)" : format("%.4f", value)
  end
end

if $PROGRAM_NAME == __FILE__
  path = ARGV.fetch(0) { abort "Usage: ruby examples/typesafe_calibration.rb DATASET.json" }
  dataset = JSON.parse(File.read(path), symbolize_names: true)
  abort "Dataset must be a JSON array" unless dataset.is_a?(Array)

  TypeSafeCalibration.run(dataset)
end
