# typed: true
# frozen_string_literal: true

module Faraday # :nodoc:
  class Adapter # :nodoc:
    class ConcurrentAdapter < ExconBase
      self.supports_parallel = true
      def self.setup_parallel_manager
        ConcurrentFaraday::ThreadedParallelManager.new
      end

      def initialize(*args)
        super
        @connect_and_request_proc = method(:connect_and_request_thread_safe)
        # Even though, this is the default on Excon
        # we want to be extra careful and set it to true.
        # We can NEVER share the underline connection socket between threads.
        @connection_options[:thread_safe_sockets] = true
        @connection_cache = Concurrent::ThreadLocalVar.new
      end

      def call(env)
        return super unless env.parallel?

        env.clear_body if env.needs_body?
        faraday_response = Faraday::Response.new

        req_opts = {
          path: env[:url].path,
          query: env[:url].query,
          method: env[:method].to_s.upcase,
          headers: env[:request_headers],
          body: read_body(env),
          span: GitHub.current_span
        }

        # The structure of promises are as following:
        # level 1: Concurrent::Promises::Future
        # level 2: ConcurrentFaraday::Promise
        #   - source: level 1. It needs a custom #wait method as level 1 isn't
        #             a promise.rb
        # level 3: ConcurrentFaraday::FutureResponse
        #   - source: level 2.
        #   - It wraps a Faraday::Response, so it can respond to all its methods.
        promise = env[:parallel_manager]
          .dispatch(env, req_opts, &@connect_and_request_proc)
          .with_timeout(env[:request][:timeout] ? env[:request][:timeout] + 0.8 : nil)

        future_response = ConcurrentFaraday::FutureResponse.new(faraday_response)
        future_response.source = promise

        # When fulfill or reject the promise, we need to update the
        # future_response with the instrumentation event.
        # So, the middleware stack can access the event from the future_response.
        on_fulfill = proc do |excon_response|
          future_response.instrument_event = promise.instrument_event
          save_response(env, excon_response.status.to_i, excon_response.body, excon_response.headers)
          faraday_response
        end
        on_reject = proc do |err|
          future_response.instrument_event = promise.instrument_event
          raise err
        end

        promise.subscribe(future_response, on_fulfill, on_reject)
        future_response.then do
          faraday_response.finish(env)
        end

        env[:parallel_manager].queue future_response
        future_response
      end

      private

      # This is a version of the parent method (connect_and_request)
      # that is thread-safe, as this method is called from multiple threads.
      def connect_and_request_thread_safe(env, req_opts)
        OpenTelemetry::Trace.with_span(req_opts.delete(:span)) do
          max_retries = 2
          begin
            c = @connection_cache.value || new_connection(env)
            # when persistent, we cache the connection, but in a thread-safe way
            if @connection_options[:persistent]
              @connection_cache.value = c
            end
            c.request(req_opts)
          rescue ::Excon::Errors::SocketError => e
            # reset connection on socket errors
            @connection_cache.value&.reset
            @connection_cache.value = nil

            raise Faraday::TimeoutError, e if e.message.match?(/\btimeout\b/)

            raise Faraday::SSLError, e if e.message.match?(/\bcertificate\b/)

            if max_retries > 0
              max_retries -= 1
              retry
            end
            raise Faraday::ConnectionFailed, e
          rescue ::Excon::Errors::Timeout => e
            raise Faraday::TimeoutError, e
          end
        end
      end

      # Note: this method is different from latest faraday-excon.
      # So it will work with previous versions of faraday.
      def amend_opts_with_timeouts!(opts, req)
        if req[:timeout]
          opts[:read_timeout]    = req[:timeout]
          opts[:connect_timeout] = req[:timeout]
          opts[:write_timeout]   = req[:timeout]
        end

        if req[:open_timeout]
          opts[:connect_timeout] = req[:open_timeout]
          opts[:write_timeout]   = req[:open_timeout]
        end
      end
    end
    register_middleware concurrent_adapter: :ConcurrentAdapter
  end
end
