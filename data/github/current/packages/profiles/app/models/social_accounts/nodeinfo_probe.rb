# typed: strict
# frozen_string_literal: true

module SocialAccounts
  # Service object that probes a user-provided host for the name of its implementing software, following the Fediverse
  # Nodeinfo protocol. See http://nodeinfo.diaspora.software/protocol.html for the full protocol and schema
  # description.
  #
  # Usage example:
  #
  #    good_result = SocialAcounts::NodeinfoProbe.call(host: "mastodon.social")
  #    good_result.success? # => true
  #    good_result.software_name # => "mastodon"
  #
  #    bad_result = SocialAccounts::NodeinfoProbe.call(host: "not.found.com")
  #    bad_result.success? # => false
  #    bad_result.software_name # => "unknown"
  class NodeinfoProbe
    REQUEST_TIMEOUT = T.let(4, Integer)
    REDIRECT_LIMIT = T.let(3, Integer)
    MAX_RESPONSE_SIZE = T.let(1024 * 1024, Integer)
    KV_TTL = T.let(3.days, ActiveSupport::Duration)

    SCHEMA_RX = T.let(%r{\Ahttp://nodeinfo\.diaspora\.software/ns/schema/(\d+)\.(\d+)/?\z}, Regexp)

    # Entry point into the probe service. Probe a host for its Nodeinfo software name, returning a Result object.
    #
    # If cached_only is true, the probe will only return a cached result, if one exists, but refrain from doing any
    # network operations. This is useful for quickly resolving common hosts without needing to launch background
    # jobs and such.
    #
    # If defer_cache_write is true, successful probe results will be stored in KV only when the returned Result's
    # perform_deferred_write method is called. This is useful for avoiding KV writes in the request path, but still
    # allowing the caller to store the result in KV in an after_response block, for example.
    sig { params(host: String, cached_only: T::Boolean, defer_cache_write: T::Boolean).returns(Result) }
    def self.call(host:, cached_only: false, defer_cache_write: false)
      new(host:, cached_only:, defer_cache_write:).call
    end

    sig { params(host: String, cached_only: T::Boolean, defer_cache_write: T::Boolean).void }
    def initialize(host:, cached_only: false, defer_cache_write: false)
      @host = host
      @cached_only = cached_only
      @defer_cache_write = defer_cache_write

      @failure_detail = T.let(nil, T.nilable(T::Hash[String, String]))
    end

    sig { returns(Result) }
    def call
      if !GitHub.nodeinfo_probe_enabled?
        report_failure_details("nodeinfo-probe-disabled")
        return failure_result
      end

      if cached = self.cached_value
        return cached_result(software_name: cached)
      elsif cached_only?
        report_failure_details("no-cached-value",
          "gh.nodeinfo.cache_key": self.kv_cache_key || "<none>",
        )
        return failure_result
      end

      # Deviate from spec to only connect to https:// hosts.
      nodeinfo_uri = URI::HTTPS.build(host: host, path: "/.well-known/nodeinfo")
      wellknown_doc = request_json_doc(nodeinfo_uri.to_s, context: "jrd-request")

      # "A client should follow the link matching the highest schema version it supports."
      document_hrefs = wellknown_doc.get_array("links").filter_map do |link_doc|
        match = link_doc.get_string("rel")&.match(SCHEMA_RX)
        next unless match

        [[match[1].to_i, match[2].to_i], link_doc.get_string("href")]
      end
      highest_document_href = document_hrefs.max_by(&:first)&.last
      report_failure_details("no-schema-link") unless highest_document_href

      # The software => name path is present in every current schema version.
      nodeinfo_doc = request_json_doc(highest_document_href, context: "nodeinfo-document")
      result = document_result(doc: nodeinfo_doc)

      # Store successful probe results in KV, either immediately or when result.perform_deferred_write is called.
      if result.success?
        key = self.kv_cache_key
        if key && result.software_name.size <= GitHub::KV::MAX_VALUE_LENGTH
          result.defer_if(defer_cache_write?) do |r|
            Profiles::Kv.store.set(key, r.software_name, expires: KV_TTL.from_now)
          end
        end
      end

      result
    end

    # Construct a String to use as a KV cache key for the provided host. Return nil instead if the key would
    # be invalid (because it's too long).
    sig { params(host: String).returns(T.nilable(String)) }
    def self.kv_cache_key(host)
      key = "nodeinfo.software.v1:#{host}"
      key.size <= GitHub::KV::MAX_KEY_LENGTH ? key : nil
    end

    # This allows us to inject a test adapter in unit and integration tests.
    cattr_accessor :faraday_conf_block, default: -> (conn) do
      # The Typhoeus adapter is backed by libcurl, which applies :timeout to the *full* request, not just connection
      # establishment and time-to-first-byte.
      #
      # For maxfilesize: see https://curl.se/libcurl/c/CURLOPT_MAXFILESIZE.html, specifically: "The file size is not
      # always known prior to download, and for such files this option has no effect even if the file transfer ends up
      # being larger than this given limit." So, this won't guard fully against DoS memory exhaustion, but it will
      # defeat some attempts and the tight :timeout value curbs the rest.
      #
      # forbid_reuse: is set to prevent libcurl from reusing connections and inheriting timeouts.
      # See https://github.com/typhoeus/typhoeus/issues/417.
      conn.adapter(:typhoeus, maxfilesize: MAX_RESPONSE_SIZE, forbid_reuse: true)
    end

    private

    sig { returns(String) }
    attr_reader :host

    # Should we perform network requests if the cache lookup is unsuccessful?
    sig { returns(T::Boolean) }
    def cached_only?
      @cached_only
    end

    # Should we write successful results to KV immediately, or defer until the returned Result's
    # perform_deferred_write method is called?
    sig { returns(T::Boolean) }
    def defer_cache_write?
      @defer_cache_write
    end

    # Record a reason that this probe failed, along with any relevant supporting information with OTel-compatible
    # keys. Callers may extract this information from the returned Result object and choose to send it to Splunk.
    #
    # Only the first failure reason and details will be recorded. Because #call is written to cascade failures -
    # methods return empty documents on failed requests, for example - one failure will cause everything after it
    # to fail as well. The first failure is the root cause, so it's the one we keep.
    sig { params(reason: String, details: T.untyped).void }
    def report_failure_details(reason, **details)
      return unless @failure_detail.nil?
      @failure_detail = details.stringify_keys
      @failure_detail["gh.nodeinfo.host"] = host
      @failure_detail["gh.nodeinfo.reason"] = reason
    end

    # Initialize a Faraday connection to the given URL, with a few common options and headers.
    sig { params(url: String).returns(Faraday::Connection) }
    def client(url)
      faraday_conf = {
        url: url,
        headers: { "Content-Type" => "application/json" },
      }
      faraday_conf[:proxy] = GitHub.external_communication_proxy_host

      GitHub::FaradayClient::External.new(faraday_conf) do |f|
        f.headers[:user_agent] = "GitHub-NodeinfoQuery/#{GitHub.current_sha.first(7)}"
        f.options[:timeout] = REQUEST_TIMEOUT

        # "A client should follow redirections by the HTTP protocol."
        f.use FaradayMiddleware::FollowRedirects, limit: REDIRECT_LIMIT, callback: -> (old_env, new_env) do
          if new_env.url.scheme != "https"
            raise RejectedRedirectError.new(old_env.url.to_s, new_env.url.to_s)
          end
          log_request(url: new_env.url.to_s, context: "redirect")
        end

        self.class.faraday_conf_block.call(f)
      end
    end

    # Construct a String to use as a KV cache key for the currently probed host. Return nil instead if the key would
    # be invalid (because it's too long). #cached_value and cache writing will be skipped in this case.
    sig { returns(T.nilable(String)) }
    def kv_cache_key
      self.class.kv_cache_key(host)
    end

    # Retrieve the previously cached software name for the currently probed host, if one exists. Returns nil if the
    # host's result has not been cached, if the cache key may not be derived, or if there is an error reading from
    # the KV database.
    sig { returns(T.nilable(String)) }
    def cached_value
      key = self.kv_cache_key
      return nil unless key

      Profiles::Kv.store.get(key).value { nil }
    end

    # Attempt to connect to a URL and return its response. Returns nil if the host is unreachable or fails an
    # SSL handshake.
    sig { params(url: T.nilable(String), context: String).returns(T.nilable(Faraday::Response)) }
    def attempt_request(url, context:)
      return nil if url.blank?

      log_request(url:, context:)
      client(url).get
    rescue RejectedRedirectError => e
      report_failure_details("refused-http-redirect",
        "http.url" => url,
        "exception.type" => e.class.name,
        "exception.message" => e.message,
        "gh.nodeinfo.redirect.location" => e.redirect_url,
      )
      nil
    rescue Faraday::ConnectionFailed, Faraday::SSLError => e
      report_failure_details("http-error",
        "http.url" => url,
        "exception.type" => e.class.name,
        "exception.message" => e.message,
      )
      nil
    end

    # Attempt to connect to a URL, returning a successful response body parsed as JSON. Any unsuccessful response,
    # document with an incorrect content type, or unparseable JSON body returns an empty document. Either way, the
    # response body is wrapped in an ArbitraryDocument so that callers can traverse the expected document structure
    # without raising exceptions.
    sig { params(url: T.nilable(String), context: String).returns(GitHub::JSON::ArbitraryDocument) }
    def request_json_doc(url, context:)
      resp = attempt_request(url, context:)
      return GitHub::JSON::ArbitraryDocument.empty unless resp

      unless resp.success?
        report_failure_details("unsuccessful-http-response",
          "http.url": resp.env.url.to_s,
          "http.status_code": resp.status,
        )
        return GitHub::JSON::ArbitraryDocument.empty
      end

      unless resp.headers["Content-Type"]&.include?("application/json")
        report_failure_details("non-json-http-response",
          "http.url": resp.env.url.to_s,
          "http.content_type": resp.headers["Content-Type"],
        )

        return GitHub::JSON::ArbitraryDocument.empty
      end

      if resp.body.bytesize > MAX_RESPONSE_SIZE
        report_failure_details("response-too-large",
          "http.url": resp.env.url.to_s,
          "http.response_content_length": resp.body.bytesize,
        )
      end

      doc = JSON.parse(resp.body, {
        max_nesting: 5,
        allow_nan: false,
        symbolize_names: false,
        create_additions: false,
      })
      GitHub::JSON::ArbitraryDocument.new(doc)
    rescue JSON::ParserError => e
      report_failure_details("json-parsing-error",
        "exception.type": e.class.name,
        "exception.message": e.message,
        "http.url": resp&.env&.url&.to_s || url || "<none>",
      )
      GitHub::JSON::ArbitraryDocument.empty
    rescue Faraday::Error => e
      report_failure_details("uncaught-network-error",
        "exception.type": e.class.name,
        "exception.message": e.message,
        "http.url": resp&.env&.url&.to_s || url || "<none>",
      )
      GitHub::JSON::ArbitraryDocument.empty
    end

    # Construct a Result object to hold the software name successfully retrieved from the cache. Returns a failed
    # Result instead of #report_failure_details has been called before.
    sig { params(software_name: String).returns(Result) }
    def cached_result(software_name:)
      return failure_result unless @failure_detail.nil?

      Result.from_cache(software_name: software_name)
    end

    # Construct a Result object to hold the software name extracted from a JSON response acquired from the host. If
    # the document does not have the expected structure, returns a failed Result instead. If #report_failure_details
    # has been called before, a failure will be returned with those details.
    sig { params(doc: GitHub::JSON::ArbitraryDocument).returns(Result) }
    def document_result(doc:)
      return failure_result unless @failure_detail.nil?

      if name = doc.get_string("software", "name")
        Result.from_response(software_name: name)
      else
        report_failure_details("missing-software-name")
        failure_result
      end
    end

    # Construct a Result object containing any details provided by a call to #report_failure_details.
    sig { returns(Result) }
    def failure_result
      Result.failure(@failure_detail || {})
    end

    sig { params(url: String, context: String).void }
    def log_request(url:, context:)
      GitHub.logger.info("nodeinfo-request",
        "gh.nodeinfo.request.context" => context,
        "http.url" => url,
      )
    end

    # Custom exception to raise on an invalid redirection attempt.
    class RejectedRedirectError < StandardError
      sig { params(url: String, redirect_url: String).void }
      def initialize(url, redirect_url)
        super("Redirect from #{url} to #{redirect_url} rejected")
        @url = url
        @redirect_url = redirect_url
      end

      sig { returns(String) }
      attr_reader :url, :redirect_url
    end

    # Support class used to represent the return value of SocialAccounts::NodeinfoProbe.call.
    class Result
      UNKNOWN_SOFTWARE = T.let("unknown".freeze, String)

      # Construct a successful Result from a software name that was retrieved from the cache.
      sig { params(software_name: String).returns(Result) }
      def self.from_cache(software_name:)
        new(software_name:, source: :cached)
      end

      # Construct a successful Result from a JSON response acquired from the host.
      sig { params(software_name: String).returns(Result) }
      def self.from_response(software_name:)
        new(software_name:, source: :fresh)
      end

      # Construct a Result for a probe that failed for any reason. Attach a Hash of supporting details with
      # OTel-compatible keys for callers to optionally log.
      sig { params(details: T::Hash[String, String]).returns(Result) }
      def self.failure(details)
        new(software_name: UNKNOWN_SOFTWARE, source: :failed, details: details)
      end

      # Return true if the probe was able to acquire the name of a host's software by any means.
      sig { returns(T::Boolean) }
      def success?
        @source.in?(%i[fresh cached])
      end

      # Return true if the probe failed for whatever reason.
      sig { returns(T::Boolean) }
      def failure?
        @source == :failed
      end

      # Return true if the probe was able to acquire the name of a host's software by cache lookup.
      sig { returns(T::Boolean) }
      def cached?
        @source == :cached
      end

      # If an evaluated condition is true, store an associated block to be executed later by a call to
      # #perform_deferred_write. Otherwise, execute the block immediately.
      sig { params(condition: T::Boolean, block: T.proc.params(result: Result).void).void }
      def defer_if(condition, &block)
        if condition
          @deferred_write = block
        else
          block.call(self)
        end
      end

      # Return true if this Result contains a deferred write action. Note that you can call #perform_deferred_write
      # anyway, but this allows callers to avoid initiating unnecessary write blocks or throttler checks when there's
      # nothing to do.
      sig { returns(T::Boolean) }
      def has_deferred_write?
        @deferred_write.present?
      end

      # Execute a block previously provided to #defer_if. No-op if no such block has been provided.
      sig { void }
      def perform_deferred_write
        @deferred_write&.call(self)
      end

      sig { returns(String) }
      attr_reader :software_name

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :details

      private

      sig { params(software_name: String, source: Symbol, details: T::Hash[String, T.untyped]).void }
      def initialize(software_name:, source:, details: {})
        @software_name = software_name
        @source = source
        @deferred_write = T.let(nil, T.nilable(T.proc.params(result: Result).void))

        @details = details
      end
    end
  end
end
