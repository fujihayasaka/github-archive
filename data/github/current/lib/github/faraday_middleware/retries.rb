# typed: true
# frozen_string_literal: true

require "date"

module GitHub
  module FaradayMiddleware
    # This code is adapted from
    # https://github.com/lostisland/faraday/blob/v0.17.6/lib/faraday/request/retry.rb
    # to include emitting metrics for the number of retries that occurred for a
    # given request, and whether that request ultimately succeeded or not.
    # It catches exceptions and retries each request a limited number of times.
    #
    # By default, it retries 2 times and handles only timeout and
    # connection-failed exceptions. It can be configured with an arbitrary
    # number of retries, a list of exceptions to handle, a retry interval, a
    # percentage of randomness to add to the retry interval, and a backoff
    # factor. These defaults are the same as those provided by the default retry
    # middleware in Faraday 0.17.6, but Reliability Engineering recommends
    # different defaults for use within GitHub. Please see the HTTP Config
    # Defaults Guidance Document for details:
    # https://thehub.github.com/epd/engineering/dev-practicals/github-http-config-defaults/
    #
    # Examples
    #
    #   Faraday.new do |conn|
    #     conn.use ::GitHub::FaradayMiddleware::Retries, client_name: "myclient", stats: ::GitHub.dogstats,
    #                          max: 2, interval: 0.05,
    #                          interval_randomness: 0.5, backoff_factor: 2,
    #                          exceptions: [CustomException, 'Timeout::Error']
    #     conn.adapter ...
    #   end
    #
    # This example will result in a first interval that is random between 0.05 and 0.075 and a second
    # interval that is random between 0.1 and 0.15
    #
    class Retries < Faraday::Middleware
      DEFAULT_EXCEPTIONS = [Errno::ETIMEDOUT, "Timeout::Error",
                            Faraday::TimeoutError, Faraday::RetriableResponse
                           ].freeze

      IDEMPOTENT_METHODS = [:delete, :get, :head, :options, :put]

      # Public: Initialize middleware
      #
      # Options:
      # client_name         - Required. Name of the client to tag retry metrics with
      # max                 - Maximum number of retries (default: 2)
      # interval            - Pause in seconds between retries (default: 0)
      # interval_randomness - The maximum random interval amount expressed
      #                       as a float between 0 and 1 to use in addition to the
      #                       interval. (default: 0)
      # max_interval        - An upper limit for the interval (default: Float::MAX)
      # backoff_factor      - The amount to multiple each successive retry's
      #                       interval amount by in order to provide backoff
      #                       (default: 1)
      # exceptions          - The list of exceptions to handle. Exceptions can be
      #                       given as Class, Module, or String. (default:
      #                       [Errno::ETIMEDOUT, 'Timeout::Error',
      #                       Faraday::TimeoutError, Faraday::RetriableResponse])
      # methods             - A list of HTTP methods to retry without calling retry_if. Pass
      #                       an empty Array to call retry_if for all exceptions.
      #                       (defaults to the idempotent HTTP methods in IDEMPOTENT_METHODS)
      # retry_if            - block that will receive the env object and the exception raised
      #                       and should decide if the code should retry still the action or
      #                       not independent of the retry count. This would be useful
      #                       if the exception produced is non-recoverable or if the
      #                       the HTTP method called is not idempotent.
      #                       (defaults to return false)
      # retry_block         - block that is executed after every retry. Request environment,
      #                       middleware options, current number of retries and the exception
      #                       is passed to the block as parameters.
      # retry_statuses      - A list of HTTP response status codes to retry. Defaults to empty,
      #                       not retrying based on status at all.
      def initialize(app, options = nil)
        super(app)
        default_options = {
          max: 2,
          interval: 0,
          max_interval: Float::MAX,
          interval_randomness: 0,
          backoff_factor: 1,
          exceptions: DEFAULT_EXCEPTIONS,
          methods: IDEMPOTENT_METHODS,
          retry_if: lambda { |_env, _exception| false },
          retry_block: lambda { |_env, _options, _retries, _exception| },
          retry_statuses: []
        }
        options = { max: options } if options.is_a?(Integer)
        @options = default_options.merge(options || {})
        @errmatch = build_exception_matcher(@options[:exceptions])
      end

      def calculate_sleep_amount(retries, env)
        retry_after     = calculate_retry_after(env)
        retry_interval  = calculate_retry_interval(retries)

        return if retry_after && retry_after > @options[:max_interval]

        retry_after && retry_after >= retry_interval ? retry_after : retry_interval
      end

      def call(env)
        GitHub.tracer.in_span("gh.faraday_client.request") do
          retries = @options[:max]
          request_exception = nil
          request_body = env[:body]
          begin
            env[:body] = request_body # after failure env[:body] is set to the response body
            @app.call(env).tap do |resp|
              raise Faraday::RetriableResponse.new(nil, resp) if @options[:retry_statuses].include?(resp.status)
            end
          rescue @errmatch => exception
            if retries > 0 && retry_request?(env, exception)
              retries -= 1
              rewind_files(request_body)
              @options[:retry_block].call(env, @options, retries, exception)
              if (sleep_amount = calculate_sleep_amount(retries + 1, env))
                sleep sleep_amount
                retry
              end
            end

            if exception.is_a?(Faraday::RetriableResponse)
              exception.response
            else
              request_exception = exception
              raise
            end
          rescue => exception # rubocop:todo Lint/GenericRescue
            # Ensure we capture exceptions we're not configured to retry on for telemetry purposes
            request_exception = exception
            raise
          ensure
            emit_telemetry(env, retries, request_exception)
          end
        end
      end

      private

      # Private: construct an exception matcher object.
      #
      # An exception matcher for the rescue clause can be any object that
      # responds to `===`.
      def build_exception_matcher(exceptions)
        Class.new do
          def self.===(other)
            @exceptions.any? do |ex|
              if ex.is_a? Module
                other.is_a? ex
              else
                other.class.to_s == ex.to_s
              end
            end
          end
        end.tap do |c|
          c.instance_variable_set(:@exceptions, exceptions)
        end
      end

      def retry_request?(env, exception)
        @options[:methods].include?(env[:method]) || @options[:retry_if].call(env, exception)
      end

      def rewind_files(body)
        return unless body.is_a?(Hash)
        body.each do |_, value|
          if value.is_a? ::Faraday::UploadIO
            value.send :rewind
          end
        end
      end

      # MDN spec for Retry-After header: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Retry-After
      def calculate_retry_after(env)
        response_headers = env[:response_headers]
        return unless response_headers

        retry_after_value = env[:response_headers]["Retry-After"]

        # Try to parse date from the header value
        begin
          datetime = DateTime.rfc2822(retry_after_value)
          datetime.to_time - Time.now.utc
        rescue ArgumentError
          retry_after_value.to_f
        end
      end

      def calculate_retry_interval(retries)
        retry_index = @options[:max] - retries
        current_interval = @options[:interval] * (@options[:backoff_factor]**retry_index)
        current_interval = [current_interval, @options[:max_interval]].min
        random_interval  = rand * @options[:interval_randomness].to_f * @options[:interval]

        current_interval + random_interval
      end

      def emit_telemetry(env, retries, exception)
        client_tag = @options[:client_name] || env.url.host
        retry_count = @options[:max] - retries
        result_tag = env.success? ? "success" : "failure"

        metric_tags = [
          "client:#{client_tag}",
          "result:#{result_tag}",
          "retried:#{retry_count > 0}"
        ]
        metric_tags << "exception:#{exception.class.name}" unless exception.nil?
        GitHub.dogstats.distribution(
          "gh.faraday_client.retries",
          retry_count,
          tags: metric_tags
        )

        span_tags = {
          "client" => client_tag,
          "result" => result_tag,
          "max_retries" => @options[:max],
          "retry_count" => retry_count,
        }

        span = GitHub.current_span
        span.status = env.success? ? OpenTelemetry::Trace::Status.ok : OpenTelemetry::Trace::Status.error
        unless exception.nil?
          span.record_exception(exception)
        end
        span.add_attributes(span_tags)
      end
    end
  end
end
