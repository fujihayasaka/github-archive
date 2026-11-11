# typed: true
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Codespaces
  # Public: Interface to the VSCS backend.
  class Client
    include GitHub::Memoizer

    class RequestError < Codespaces::Error
      attr_reader :rollup_components

      def initialize(msg = nil, rollup_components: nil)
        @rollup_components = rollup_components || []
        super(msg)
      end

      def failbot_context
        if rollup_components.any?
          all_rollup_components = [self.class.name] + rollup_components
          { rollup: Digest::SHA256.hexdigest(all_rollup_components.join("|")) }
        else
          {}
        end
      end
    end

    class TimeoutError < RequestError; end

    class ConnectionFailed < RequestError; end

    class BadResponseError < RequestError
      attr_reader :status, :error_body, :error_codes

      def initialize(msg, status = nil, error_body = nil, rollup_components: nil)
        @status = status
        @error_body = error_body
        # The error code could be either a bare int or an array of ints
        @error_codes = bad_response_vscs_error_codes(error_body)
        super(msg, rollup_components:)
      end

      def unprocessable_entity?
        status == 422
      end

      private

      def bad_response_vscs_error_codes(error_body)
        error_codes = []
        raw_codes = Array(error_body)
        begin
          error_codes = raw_codes.map do |i|
            Integer(i)
          end
        rescue ArgumentError, TypeError
        end
        error_codes
      end
    end

    class EncryptionKeyError < Codespaces::Error; end

    DEFAULT_TIMEOUTS = { open_timeout: 2, timeout: 8 }.freeze
    DEFAULT_RETRY_CONFIG = {
      max: 3,
      interval: 0.05,
      backoff_factor: 2,
      exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError],
    }

    def self.default_timeouts
      DEFAULT_TIMEOUTS
    end

    def self.default_retry_config
      DEFAULT_RETRY_CONFIG
    end

    def self.timeouts
      Thread.current[:codespace_client_timeouts] || default_timeouts
    end

    def self.retry_config
      Thread.current[:codespace_client_retry_config] || default_retry_config
    end

    def self.with_timeouts(timeouts)
      if timeouts.nil?
        yield
      else
        current_timeouts = self.timeouts
        self.timeouts = timeouts
        begin
          yield
        ensure
          self.timeouts = current_timeouts
        end
      end
    end

    def self.with_retry_config(retry_config)
      if retry_config.nil?
        yield
      else
        current_retry_config = self.retry_config
        self.retry_config = retry_config
        begin
          yield
        ensure
          self.retry_config = current_retry_config
        end
      end
    end

    attr_reader :timeouts, :retry_config

    def initialize(timeouts: nil, retry_config: nil)
      @timeouts = timeouts.presence || self.class.timeouts
      @retry_config = retry_config.presence || self.class.retry_config
    end

    def logger
      @logger ||= ClientLogger.new do |l|
        # We don't ever want to log the Authorization header.
        l.sensitive_keys("Authorization")
        # Allows subclasses to override logger and call `super { }` to augment what we've done here
        yield l if block_given?
      end
    end

    protected

    # Internal: Fetches a token from KV if present or runs code to generate the token
    # and stores it in KV.
    #
    # key_segments - A list of identifying information for this token to generate the cache key.
    # type:        - The token type String used for the key and instrumentation.
    # force:       - Force a fresh token to be requested
    # block        - A block to run in order to generate the token. Should return a tuple of the
    #                token and the expiration time in seconds.
    #
    # Returns a token String or String of json token data.
    def cache_token(*key_segments, type:, force: false, encrypted: false, encryptor: nil, &block)
      force_write_token = FeatureFlag.vexi.enabled_or_raise?(:codespaces_force_no_cache_cascade_token) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      cache_key = Codespaces::TokenCache.generate_key(key_segments, type: type)
      if encrypted && !encryptor
        encryptor = default_token_encryptor
      end
      if force_write_token
        GitHub.dogstats.increment("codespaces.client.cache", tags: ["type:#{type}", "result:miss"])

        data, expires_in = yield

        Codespaces::TokenCache.write(data: data, expires_in: expires_in, cache_key: cache_key, encrypted: encrypted, encryptor: encryptor)
      else
        if !force && cached_data = Codespaces::TokenCache.read(cache_key, encryptor: encryptor, encrypted: encrypted)
          GitHub.dogstats.increment("codespaces.client.cache", tags: ["type:#{type}", "result:hit"])

          cached_data
        else
          GitHub.dogstats.increment("codespaces.client.cache", tags: ["type:#{type}", "result:miss"])

          data, expires_in = yield

          Codespaces::TokenCache.write(data: data, expires_in: expires_in, cache_key: cache_key, encrypted: encrypted, encryptor: encryptor)
        end
      end
    end

    # These three variants are intended to wrap specific requests to augment any global filtering being done.
    def with_sensitive_log_data(data, &block)
      logger.with_sensitive_data(data, &block)
    end

    def with_sensitive_log_keys(*keys, &block)
      logger.with_sensitive_keys(*keys, &block)
    end

    def with_filterered_log_data(*filters, &block)
      logger.with_filters(*filters, &block)
    end

    def with_response_timing(dogstat, tags: [], &block)
      if tags.none? { |t| t.start_with?("caller:") }
        if Rails.env.development?
          raise "Ensure the caller is properly tagged"
        else
          tags << "caller:unknown"
        end
      end

      start_time = GitHub::Dogstats.monotonic_time
      timeout = false
      begin
        response = yield
        tags << "status:#{response.status}"
      rescue Faraday::TimeoutError => e
        timeout = true
        raise e
      ensure
        GitHub.dogstats.distribution("#{dogstat}.latency", GitHub::Dogstats.duration(start_time), tags: tags + ["timeout:#{timeout}"])
      end

      response
    end

    def request_err_message(message_title, method, description = nil)
      # Definitely not the cleanest way to reuse the log scrubbing to get a safe URL to send here but
      # it works for now.
      url = logger.scrubber.scrub(logger.request_context[:request_url])
      request_id = logger.request_context[:faraday_response_id]
      status = logger.request_context[:response_status]
      [
        "#{message_title} for #{method.to_s.upcase} #{url}",
        ("Status: #{status}" if status),
        ("Request-ID: #{request_id}" if request_id),
        (description if description),
      ].compact.join(", ")
    end

    private

    def default_token_encryptor
      return @token_encryptor if defined?(@token_encryptor)
      begin
        token_encryption_key = Base64.decode64(GitHub.codespaces_token_encryption_key)
        @token_encryptor = RbNaCl::SimpleBox.from_secret_key(token_encryption_key)
      rescue EncodingError, RbNaCl::LengthError
        raise EncryptionKeyError, "Encryption key is missing or invalid."
      end
    end

    def setup_connection_adapter(f, adapter, keepalive)
      if adapter == :typhoeus
        f.adapter adapter
      else
        f.adapter adapter, keepalive: keepalive
      end
    end

    def connection_for(url, adapter: :excon, keepalive: false)
      Faraday.new(url: url, request: timeouts) do |f|
        yield f if block_given?
        f.use(GitHub::FaradayMiddleware::RequestID)
        f.request(:retry, retry_options)
        f.use ResponseLogger, logger
        f.use LinkSentryToKusto
        setup_connection_adapter(f, adapter, keepalive)
      end
    end

    def service_name
      "#{self.class.name&.underscore}"
    end

    def retry_options
      retry_proc = proc { |env, _options, _retries, exc|
        host = env.url.host
        exc_cls = exc.class
        GitHub.dogstats.increment(
          "codespaces.client.connection_retry",
          tags: ["host:#{host}", "exception:#{exc_cls}"],
        )
      }

      options = retry_config || self.class.retry_config
      options[:retry_block] = retry_proc

      options
    end

    class << self
      private

      def timeouts=(timeouts)
        Thread.current[:codespace_client_timeouts] = timeouts
      end

      def retry_config=(retry_config)
        Thread.current[:codespace_client_retry_config] = retry_config
      end
    end
  end
end
