# frozen_string_literal: true

require "json"
require "net/http"
require "time"
require "uri"
require_relative "request_tracking"

module RubricLLM
  module SystemOne
    class Client
      BODY_EXCERPT_LENGTH = 500
      MAX_RETRY_AFTER = 60.0
      TRANSIENT_EXCEPTIONS = [Net::OpenTimeout, Net::ReadTimeout, Timeout::Error].freeze

      attr_reader :usage_attempts

      def initialize(config:, transport: nil, sleeper: Kernel)
        @config = config
        @transport = transport || method(:perform_http)
        @sleeper = sleeper
        @request_tracking = RequestTracking.new
        @usage_attempts = @request_tracking.usage_attempts
      end

      def call(state:, questions:, model: @config.decision_model)
        validate_call!(state, questions, model)
        indexed = questions.to_h { |question| [question.id, question] }
        payload = { state:, model:, questions: indexed.transform_values(&:to_h) }
        started = monotonic_time
        parsed = request_with_retries(payload)
        build_response(parsed, indexed, ((monotonic_time - started) * 1000).round(1))
      rescue ConfigurationError, JudgeError => e
        raise sanitized(e), cause: nil
      rescue StandardError => e
        raise sanitized(JudgeError.new("System One call failed: #{e.class}: #{e.message}")), cause: nil
      end

      private

      def validate_call!(state, questions, model)
        @config.validate!
        validate_credentials_and_model!(model)
        validate_questions!(questions)
        raise ConfigurationError, "System One state must be a String or Hash" unless state.is_a?(String) || state.is_a?(Hash)

        raise ConfigurationError, "System One state must be JSON-compatible" unless json_value?(state)
      end

      def json_value?(value)
        case value
        when String, Integer, TrueClass, FalseClass, NilClass then true
        when Float then value.finite?
        when Array then value.all? { |item| json_value?(item) }
        when Hash
          value.all? { |key, item| (key.is_a?(String) || key.is_a?(Symbol)) && json_value?(item) }
        else false
        end
      end

      def validate_credentials_and_model!(model)
        if @config.typesafe_api_key.nil? || @config.typesafe_api_key.to_s.strip.empty?
          raise ConfigurationError, "typesafe_api_key is required for System One calls"
        end
        return if model.is_a?(String) && !model.strip.empty?

        raise ConfigurationError, "System One model must be a non-empty string"
      end

      def validate_questions!(questions)
        unless questions.is_a?(Array) && !questions.empty? && questions.all?(Question)
          raise ConfigurationError, "System One questions must be a non-empty Array of Question objects"
        end

        return if questions.map(&:id).uniq.length == questions.length

        raise ConfigurationError, "System One question ids must be unique"
      end

      def request_with_retries(payload)
        attempts = 0
        loop do
          attempts += 1
          begin
            uri = endpoint
            request = build_request(payload)
            response = @request_tracking.with_unknown_on_error(payload[:model]) do
              @transport.call(uri:, request:, timeout: @config.typesafe_timeout)
            end
          rescue *TRANSIENT_EXCEPTIONS => e
            raise JudgeError, "System One request timed out: #{e.message}" if attempts > @config.max_retries

            backoff(attempts)
            next
          end

          status = @request_tracking.with_unknown_on_error(payload[:model]) { Integer(response.code) }
          if status.between?(200, 299)
            parsed = @request_tracking.with_unknown_on_error(payload[:model]) { parse_body(response.body) }
            return @request_tracking.capture_response(payload[:model], parsed)
          end

          @request_tracking.record_unknown(payload[:model])
          error = http_error(status, response.body)
          raise error unless retryable_status?(status) && attempts <= @config.max_retries

          backoff(attempts, response:)
        end
      end

      def endpoint
        URI.parse(@config.typesafe_base_url).tap { |base| base.path = "#{base.path.sub(%r{/+\z}, "")}/systemone" }
      end

      def build_request(payload)
        request = Net::HTTP::Post.new(endpoint)
        request["Authorization"] = "Bearer #{@config.typesafe_api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        request
      end

      def perform_http(uri:, request:, timeout:)
        options = { use_ssl: uri.scheme == "https", open_timeout: timeout, read_timeout: timeout, write_timeout: timeout }
        Net::HTTP.start(uri.host, uri.port, **options) do |http|
          http.request(request)
        end
      end

      def parse_body(body)
        parsed = JSON.parse(body.to_s)
        raise JudgeError, "System One response must be a JSON object" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise JudgeError, "System One response was not valid JSON: #{e.message}"
      end

      def build_response(raw, questions, latency_ms)
        model = raw["model"]
        raise JudgeError, "System One response model must be non-empty" unless model.is_a?(String) && !model.strip.empty?

        raw_answers = raw["answers"]
        raise JudgeError, "System One response answers must be an object" unless raw_answers.is_a?(Hash)
        raise JudgeError, "System One response question ids do not match the request" unless raw_answers.keys.sort == questions.keys.sort

        answers = questions.to_h { |id, question| [id, build_answer(raw_answers.fetch(id), question)] }
        usage = @request_tracking.validate_usage!(raw["usage"])
        Response.new(answers:, usage:, model:, latency_ms:, raw:)
      end

      def build_answer(raw, question)
        raise JudgeError, "System One answer for #{question.id.inspect} must be an object" unless raw.is_a?(Hash)
        raise JudgeError, "System One answer type does not match question #{question.id.inspect}" unless raw["type"] == question.type.to_s

        klass = { noul: Answer::Noul, choice: Answer::Choice, score: Answer::Score }.fetch(question.type)
        question.type == :noul ? klass.new(raw) : klass.new(raw, question)
      end

      def retryable_status?(status)
        status == 429 || status >= 500
      end

      def http_error(status, body)
        excerpt = body.to_s.gsub(@config.typesafe_api_key.to_s, "[REDACTED]")[0, BODY_EXCERPT_LENGTH]
        JudgeError.new("System One HTTP #{status}: #{"too large; reduce state/questions. " if status == 413}#{excerpt}")
      end

      def backoff(attempt, response: nil)
        @sleeper.sleep(retry_after_delay(response) || (@config.retry_base_delay * (2**(attempt - 1))))
      end

      def retry_after_delay(response)
        return unless response

        milliseconds = Float(response["retry-after-ms"], exception: false)
        delay = milliseconds / 1000.0 if milliseconds&.between?(0, MAX_RETRY_AFTER * 1000)
        retry_after = response["retry-after"]
        delay ||= Float(retry_after, exception: false) if retry_after
        delay ||= [Time.httpdate(retry_after) - Time.now, 0].max if retry_after
        delay if delay&.finite? && delay.between?(0, MAX_RETRY_AFTER)
      rescue ArgumentError, TypeError
        nil
      end

      def sanitized(error)
        key = @config.typesafe_api_key.to_s
        message = error.message.to_s
        message = message.gsub(key, "[REDACTED]") unless key.empty?
        error.class.new(message)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
