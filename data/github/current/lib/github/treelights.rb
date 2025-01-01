# typed: true
# frozen_string_literal: true
require "treelights"
require "treelights/gzip_request"
require "sinatra"
require "set"

module GitHub
  class Treelights
    SERVICE_URL = "#{GitHub.treelights_url}/twirp".freeze
    SERVICE_NAME = "treelights".freeze

    # Time in seconds for which the server info should be locally cached
    SERVER_INFO_TTL = 5 * 60

    MAX_DIRECTIVES = 200_000
    MAX_DIRECTIVES_PER_LINE = 1000

    class RPCError < StandardError; end

    # Private: The maximum amount of text that should be sent to Treelights,
    # per second of of timeout. It can take significant time to serialize,
    # transmit, and deserialize documents from Rails to Treelights. And
    # Treelights has a limited throughput. So we avoid sending documents that
    # are unlikely to be successfully highlighted within the time limit.
    MAXIMUM_BYTES_PER_SECOND = 6 * 1024 * 1024

    class << self
      # Public: Cache key prefix for caching syntax highlighted markup.
      def cache_key
        refresh_server_info
        @cache_key
      end

      # Public: Cache key prefix for caching syntax highlighted markup in
      # darkship mode.
      def darkship_cache_key
        refresh_server_info
        @darkship_cache_key
      end

      # Public: Syntax highlight some text with treelights.
      #
      # scope   - Textmate scope string identifying the language of the text.
      # text    - String containing source code to highlight
      # timeout - Time limit in seconds for highlighting the document
      # mode    - Symbol indicating which highlighting algorithms are allowed.
      #           By default, Tree-sitter is used for supported languages. Pass
      #           :TEXTMATE_ONLY to disable the Tree-sitter highlighter.
      #
      # Returns an Array of Strings (html safe String lines).
      def highlight(scope, text, timeout: nil, mode: :DEFAULT)
        GitHub.tracer.in_span("GitHub::Treelights.highlight", kind: :internal) do |_span|
          highlight_many([scope], [text], timeout: timeout, mode: mode).first
        end
      end

      # Public: Syntax highlight multiple documents.
      #
      # scopes  - Array of textmate scope strings identifying the language of each text.
      # texts   - Array of strings containing source code to highlight.
      # timeout - Time limit in seconds for highlighting each document
      # mode    - Symbol indicating which highlighting algorithms are allowed.
      #           By default, Tree-sitter is used for supported languages. Pass
      #           :TEXTMATE_ONLY to disable the Tree-sitter highlighter.
      #
      # Returns an Array of arrays of strings (html safe String lines).
      def highlight_many(scopes, texts, timeout: nil, mode: :DEFAULT, highlight_format: :HTML)
        GitHub.tracer.in_span("GitHub::Treelights.highlight_many", kind: :internal) do |span|
          send_treelights_request(scopes, texts, span, timeout: timeout) do |allowed_scopes, allowed_texts, timeout_ms|
            client.highlight(
              allowed_scopes,
              allowed_texts,
              timeout: timeout_ms,
              mode: mode
            ).map do |lines|
              lines&.map(&:html_safe)
            end
          end
        end
      end

      # Public: Get a list of highlighted tokens in some text with treelights.
      #
      # scope   - Textmate scope string identifying the language of the text.
      # text    - String containing source code to highlight
      # timeout - Time limit in seconds for highlighting the document
      #
      # Returns an Array of Arrays.
      # Each element of the outer array represents a line of code.
      # Each element of the inner array represents a highlighted token on that line.
      def styling_directives(scope, text, timeout: nil)
        GitHub.tracer.in_span("GitHub::Treelights.styling_directives", kind: :internal) do |_span|
          styling_directives_for_many([scope], [text], timeout: timeout)&.first
        end
      end

      # Public: Get a list of highlighted tokens in some text with treelights.
      #
      # scope   - Textmate scope string identifying the language of the text.
      # text    - String containing source code to highlight
      # timeout - Time limit in seconds for highlighting the document
      #
      # Returns an Array of Arrays.
      # Each element of the outer array represents a line of code.
      # Each element of the inner array represents a highlighted token on that line.
      # Public: Get a list of highlighted tokens in multiple documents with treelights.
      #
      # scopes  - Array of textmate scope strings identifying the language of each text.
      # texts   - Array of strings containing source code to highlight.
      # timeout - Time limit in seconds for highlighting each document
      #
      # Returns an Array of Arrays of Arrays.
      # Each element of the outermost array represents a document.
      # Each element of the second array represents a line of code.
      # Each element of the innermost array represents a highlighted token on that line.
      def styling_directives_for_many(scopes, texts, timeout: nil)
        GitHub.tracer.in_span("GitHub::Treelights.styling_directives_for_many", kind: :internal) do |span|
          send_treelights_request(scopes, texts, span, timeout: timeout) do |allowed_scopes, allowed_texts, timeout_ms|
            documents = client.styling_directives(
              allowed_scopes,
              allowed_texts,
              timeout: timeout_ms,
            )

            transform_styling_directives(documents)
          end
        end
      end

      def transform_styling_directives(documents)
        return nil unless documents

        num_dir = 0

        directives = documents.map do |document_lines|
          next nil unless document_lines

          document_lines.map do |line|
            next [] unless line
            next [] if num_dir >= MAX_DIRECTIVES

            directives_in_line = []
            line.directives.each do |directive|
              break if num_dir >= MAX_DIRECTIVES
              break if directives_in_line.size >= MAX_DIRECTIVES_PER_LINE

              num_dir += 1
              directives_in_line << {
                s: directive.start.utf16,
                e: directive.end.utf16,
                c: directive.css_class
              }
            end
            directives_in_line
          end
        end

        directives
      end

      # Public: Get a `Set` of all of the scope strings recognized by the server.
      def valid_scopes
        refresh_server_info
        @valid_scopes
      end

      # Public: Forget everything. Useful for tests.
      def reset
        @server_info_fetch_time = nil
        @cache_key = nil
        @darkship_cache_key = nil
        @valid_scopes = nil

        # Sometimes pre-prep stages (before Treelights has been stubbed!) can
        # cause the circuit breaker to trip, failing requests against a
        # non-existent local Treelights instance, meaning requests are failed
        # later even though we've stubbed out the responses by then.
        Resilient::CircuitBreaker.get(SERVICE_NAME).reset
      end

      private

      INFO_ERRORS = [
        Faraday::Error,
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        Faraday::SSLError,
        Timeout::Error,
        ::Github::Treelights::Client::ResponseError,
      ]

      def send_treelights_request(scopes, texts, span, timeout: nil)
        # Limit the total amount of text that is sent to Treelights,
        # so that we avoid sending text that is unlikely to be highlighted
        # within the timeout.
        if timeout
          timeout_ms = (timeout * 1000).to_i
          total_bytes = 0
          maximum_bytes = MAXIMUM_BYTES_PER_SECOND * timeout
          allowed_doc_count = texts.count do |text|
            total_bytes += text.bytesize
            total_bytes <= maximum_bytes
          end
        else
          timeout_ms = nil
          allowed_doc_count = texts.length
        end

        highlighted = yield scopes.first(allowed_doc_count), texts.first(allowed_doc_count), timeout_ms

        return nil if highlighted.nil?

        # Ensure that the returned array has the same length as the input
        # arrays, in case any inputs were omitted from the treelights request
        # due to the total size limit.
        highlighted.fill(nil, highlighted.length...texts.length)
      rescue Faraday::TimeoutError, Timeout::Error => error
        GitHub::Logger.log(at: "treelights.timeout_error", error: error)
        GitHub.dogstats.increment("rpc.treelights.timeouts")
        span.add_event("exception", attributes: { "exception.type" => error.class.name })
        raise RPCError
      rescue Faraday::SSLError, Faraday::Error, Faraday::ConnectionFailed => error
        GitHub::Logger.log(at: "treelights.connection_error", error: error)
        GitHub.dogstats.increment("rpc.treelights.connection_errors")
        span.add_event("exception", attributes: { "exception.type" => error.class.name })
        raise RPCError
      rescue ::Github::Treelights::Client::ResponseError
        GitHub::Logger.log(at: "treelights.response_error", error: error)
        GitHub.dogstats.increment("rpc.treelights.response_errors")
        span.add_event("exception", attributes: { "exception.type" => error.class.name })
        raise RPCError
      end

      def refresh_server_info
        time = Time.now
        unless @server_info_fetch_time && time - @server_info_fetch_time < SERVER_INFO_TTL
          info = GitHub.tracer.in_span("GitHub::Treelights.info", kind: :internal) do |span|
            T::let(client.info, { version: String, scopes: T::Enumerable[String] })
          rescue *INFO_ERRORS => error
            GitHub::Logger.log(at: "treelights.info.error", error: error)
            span.add_event("exception", attributes: { "exception.type" => error.class.to_s })
            { version: "unknown", scopes: [] }
          end

          @cache_key = "treelights.#{::Github::Treelights::VERSION}.#{info[:version]}".freeze
          @darkship_cache_key = "treelights-darkship.#{::Github::Treelights::VERSION}.#{info[:version]}".freeze
          @valid_scopes = Set.new(info[:scopes]).freeze
          @server_info_fetch_time = time
        end
      end

      def client
        @client ||= begin
          connection = Faraday.new(url: SERVICE_URL) do |conn|
            conn.request(:retry,
              max: 3,
              interval: 0.1,
              backoff_factor: 2,
              exceptions: [Faraday::ConnectionFailed],
              methods: [:post],
            )
            conn.use ::Github::Treelights::GzipRequest
            conn.use GitHub::FaradayMiddleware::RequestID
            conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
            conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
              instrumenter: GitHub,
              error_threshold_percentage: 5,
            }
            conn.adapter :typhoeus
            conn.options[:open_timeout] = 0.1 # connection open timeout in seconds.
            conn.options[:timeout] = 5.5      # read timeout in seconds.
          end
          ::Github::Treelights::Client.new(connection)
        end
      end
    end
  end
end
