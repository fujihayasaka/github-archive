# typed: true
# frozen_string_literal: true

# The ClientLogger is used by all codespace clients making requests to VSCS/ARM. It is responsible for logging as much
# information about our requests and responses as needed for debugging errors in production while also ensuring that
# we do not log any sensitive data.
#
# ClientLogger supports three modes of scrubbing log data. All three modes can be combined as needed.
# 1. `filter` allows you to set up regular expression to find/replace data in requests/responses. This is the standard
#    filtering mechansism supported by the basic Faraday response logging middleware and should only be used when we
#    must filter out data that we cannot know ahead of time.
# 2. `sensitive_keys` allows you to configure hash keys whose values will be filtered from logged data. Currently this
#    would include request and response headers as long as JSON request or response bodies.
#    Example: logger.with_sensitive_keys "Authorization" { logger.log({ Authorization: "Bearer token-here" }) }
#    Log Output: "{ \"Authorization\"=>\"[FILTERED]\" }"
# 3. `with_sensitive_data` leverages the same scrubbing mechanism as Failbot to scrub known sensitive data before
#    logging it. It expects a hash of keys naming the data and the data's value.
#    Example: logger.with_sensitive_data client_secret: "shhh secret" { logger.log({ client_secret: "shhh secret" }) }
#    Log Output: "{ \"client_secret\"=>\"[FILTERED CLIENT SECRET]\" }"
#
module Codespaces
  class ClientLogger
    extend T::Sig

    CODESPACES_REQUEST_ID_PREFIX = "cs-".freeze
    CODESPACES_REQUEST_ID_HEADER = "X-Request-Id".freeze
    CODESPACES_RESPONSE_ID_HEADERS = %w(vssaas-request-id x-ms-correlation-request-id x-ms-request-id)
    GITHUB_REQUEST_ID_HEADER = "X-GitHub-Request-Id".freeze

    class Scrubber
      extend T::Sig

      sig { void }
      def initialize
        @filter = T.let([], T::Array[[Regexp, String]])
        @sensitive_keys = T.let([], T::Array[T.any(String, Symbol)])
      end

      # Specify filters to configure regexps that will be applied to all logged data. This is the same as the base Faraday
      # logging middleware.
      sig { params(filter_word: Regexp, filter_replacement: String).void }
      def filter(filter_word, filter_replacement)
        @filter.push([filter_word, filter_replacement])
      end

      sig { params(filters: [Regexp, String], block: T.proc.params(arg0: Scrubber).returns(T.untyped)).returns(T.untyped) }
      def with_filters(*filters, &block)
        original_filters = @filter.dup
        T.unsafe(filters).each { |f| self.filter(f[0], f[1]) }

        yield self
      ensure
        @filter = T.must(original_filters)
      end

      # Specify sensitive keys to have the explicitly stripped out of any hashes we are logging including
      # headers and JSON bodies.
      sig { params(keys: T.any(String, Symbol)).void }
      def sensitive_keys(*keys)
        T.unsafe(@sensitive_keys).push(*keys)
      end

      sig { params(keys: T.any(String, Symbol), block: T.proc.params(arg0: Scrubber).returns(T.untyped)).returns(T.untyped) }
      def with_sensitive_keys(*keys, &block)
        original_sensitive_keys = @sensitive_keys.dup
        T.unsafe(self).sensitive_keys(*keys)

        yield self
      ensure
        @sensitive_keys = T.must(original_sensitive_keys)
      end

      # Leverages the SensitiveData functionality used by Failbot to scrub data before it is logged. This requires
      # knowing the value of the sensitive data ahead of time e.g. an authentication token or such. This method of
      # filtering should be prefered because it leaves the most information possible (compared to sensitive_keys)
      # while at the same time being more foolproof than filters which use regexps.
      sig { params(data: T::Hash[T.any(String, Symbol), String], block: T.proc.params(arg0: Scrubber).returns(T.untyped)).returns(T.untyped) }
      def with_sensitive_data(data, &block)
        SensitiveData.context.push(data) do
          yield self
        end
      end

      sig { params(output: T.untyped).returns(T.any(Hash, Array, String)) }
      def scrub(output)
        case output
        when Hash
          # Scrub out hash keys specified in `sensitive_keys`
          @sensitive_keys.each do |key|
            output[key.to_s]   = "[FILTERED #{key.to_s.upcase}]" if output.key?(key.to_s)
            output[key.to_sym] = "[FILTERED #{key.to_s.upcase}]" if output.key?(key.to_sym)
          end
          output = output.transform_values { |v| scrub(v) }
        when Array
          # Scrub all elements of the array
          output = output.map { |v| scrub(v) }
        else
          # Scrub value as specified with `with_sensitive_data` using SensitiveData
          output = SensitiveData.scrub(output.to_s, Thread.current) if SensitiveData.context
          # Apply filters last to scrub data
          @filter.each do |pattern, replacement|
            output = output.to_s.gsub(pattern, replacement)
          end
        end
        output
      end
    end

    attr_reader :scrubber

    delegate :filter, :with_filters, :sensitive_keys, :with_sensitive_keys, :with_sensitive_data, to: :scrubber

    sig { params(logger: T.untyped, catalog_service: String, scrubber: Scrubber).void }
    def initialize(logger: GitHub.logger, catalog_service: "github/codespaces", scrubber: Scrubber.new)
      @logger = logger
      @catalog_service = catalog_service
      @scrubber = scrubber
      self.log_context = {}
      yield self if block_given?
    end

    sig { returns(T::Hash[Symbol, T.any(Hash, Array, String, Integer, NilClass)]) }
    def request_context
      @request_context ||= {}
    end

    sig { params(env: T.untyped).void }
    def request(env)
      reset!
      request_context[:previous_requests] = request_chain.dup
      track_requests!(env)
      request_context[:request_id] = env.request_headers[GITHUB_REQUEST_ID_HEADER] if env.request_headers[GITHUB_REQUEST_ID_HEADER]
      request_context[:faraday_request_id] = request_id
      request_context[:request_method] = env.method.upcase
      request_context[:request_url] = env.url
      # Stash the original request details so we can log them on errors or unsuccessful requests.
      @request_headers = env.request_headers.dup
      @request_body = env[:request_body] || env[:body]
      # We don't emit logs until response/error is called by the middleware.
    end

    sig { params(env: T.untyped).void }
    def response(env)
      if !env.response.success?
        request_context[:request_headers] = @request_headers
        request_context[:request_body] = dump_body(@request_body)
      end
      request_context[:faraday_response_id] = response_id(env.response_headers)
      request_context[:response_status] = env.status
      if !env.response.success?
        request_context[:response_headers] = env.response_headers
        request_context[:response_body] = dump_body(env[:response_body] || env[:body])
      end
      if !env.response.success?
        fatal(request_context)
      else
        info(request_context)
      end
    end

    sig { params(error: StandardError).void }
    def error(error)
      request_context[:request_headers] = @request_headers
      request_context[:request_body] = dump_body(@request_body)
      request_context[:request_error_class] = error.class.name
      request_context[:request_error_message] = error.full_message(highlight: false).strip

      if error.respond_to?(:response) && response = T.unsafe(error).response
        request_context[:response_status] = response[:status]
        request_context[:faraday_response_id] = response_id(response[:headers])
        request_context[:response_headers] = response[:headers]
        request_context[:response_body] = dump_body(response[:body])
      end
      fatal(request_context)
    end

    sig { params(context: T::Hash[T.any(String, Symbol), T.any(String, Integer)]).void }
    def log_context=(context)
      @log_context = context.reverse_merge(
        "gh.catalog_service" => @catalog_service
      )
    end

    sig { params(data: T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)]), blk: T.proc.returns(T.untyped)).void }
    def log_context(data, &blk)
      @logger.with_named_tags(scrub(data), &blk)
    end

    sig { params(data: T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)])).void }
    def debug(data)
      log_context(@log_context) do
        @logger.debug(scrub(data))
      end
    end

    sig { params(data: T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)])).void }
    def info(data)
      log_context(@log_context) do
        @logger.info(scrub(data))
      end
    end

    alias_method :log, :info

    sig { params(data: T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)])).void }
    def warn(data)
      log_context(@log_context) do
        @logger.warn(scrub(data))
      end
    end

    sig { params(data: T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)])).void }
    def fatal(data)
      log_context(@log_context) do
        @logger.fatal(scrub(data))
      end
    end

    private

    sig { void }
    def reset!
      @request_headers = nil
      @request_body = nil
      @request_context = nil
      @request_id = nil
    end

    sig { returns(T::Array[String]) }
    def request_chain
      @request_chain ||= []
    end

    sig { returns(String) }
    def request_id
      @request_id ||= "#{CODESPACES_REQUEST_ID_PREFIX}#{SecureRandom.uuid}"
    end

    sig { params(response_headers: T::Hash[String, String]).returns(T.nilable(String)) }
    def response_id(response_headers)
      response_headers.transform_keys(&:downcase).values_at(*CODESPACES_RESPONSE_ID_HEADERS).compact.first
    end

    sig { params(env: T.untyped).void }
    def track_requests!(env)
      # Give every client request its own UUID independent of the X-GitHub-Request-Id. There are frequently multiple
      # requests made to VSCS for a single client request, so this makes it easier to track the lifecycle of requests.

      if !env.request_headers[CODESPACES_REQUEST_ID_HEADER]
        env.request_headers[CODESPACES_REQUEST_ID_HEADER] = request_id
      end
      request_chain.push(request_id)
    end

    sig { params(data: T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)])).returns(T.any(String, T::Hash[T.any(String, Symbol), T.any(String, Integer, Hash, Array, NilClass)])) }
    def scrub(data)
      data = scrubber.scrub(data)
      return data unless data.respond_to?(:transform_values)

      data.transform_values do |v|
        case v
        when Hash
          v.to_json
        else
          v
        end
      end
    end

    sig { params(body: T.any(String, Hash, Integer, NilClass, Array)).returns(T.any(String, Hash, Integer, NilClass, Array)) }
    def dump_body(body)
      return unless body.present?

      begin
        # Request and response bodies should be JSON...
        GitHub::JSON.parse(body)
      rescue Yajl::ParseError
        # Except when they're not...
        if body.respond_to?(:to_str)
          T.unsafe(body).to_str.strip
        else
          T.unsafe(body).pretty_inspect.strip
        end
      end
    end
  end
end
