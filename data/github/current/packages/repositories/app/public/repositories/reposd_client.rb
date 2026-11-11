# typed: strict
# frozen_string_literal: true

module Repositories
  class ReposdClient
    sig { returns(T::Boolean) }
    def self.force_encoding_to_binary?
      false
    end

    sig { void }
    def initialize
      options = if GitHub.environment.fetch("SKIP_REPOSD", "false")
        # give us 5 minutes to make it easier to debug inside reposd
        {
          request: {
            open_timeout: 10,
            timeout: 300,
          }
        }
      else
        nil
      end
      @reposd_client = T.let(GitHub::FaradayClient.internal("reposd", GitHub.reposd_url, options), Faraday::Connection) # has a 1.3 second request timeout by default
    end

    sig { params(path: String, params: T.untyped, headers: T.untyped, method: T.untyped).returns(T.untyped) }
    def api_request(path:, params:, headers:, method:)
      request_headers = headers.select { |key, _| key.start_with?("HTTP_") && key != "HTTP_HOST" }.transform_keys { |key| key.sub("HTTP_", "").upcase.gsub("_", "-") }

      # Forward REMOTE_ADDR as X-Forwarded-For so reposd sees the original client IP
      # for IP allowlist checks. REMOTE_ADDR is a Rack env variable, not an HTTP header,
      # so it won't be picked up by the HTTP_ prefix filter above.
      if headers["REMOTE_ADDR"].present? && !request_headers.key?("X-FORWARDED-FOR")
        request_headers["X-FORWARDED-FOR"] = headers["REMOTE_ADDR"]
      end

      # convert params like "ref=master" into a hash
      params = URI.decode_www_form(params).to_h if params.is_a?(String) && method != "POST"
      if self.class.force_encoding_to_binary?
        params.transform_values { |v|  v.force_encoding(Encoding::BINARY) }
      end

      # Only set the HMAC header if one isn't already present in the request,
      # so tests can provide their own (valid or invalid) HMAC for IP allow list testing.
      unless request_headers.key?("REQUEST-HMAC")
        request_headers["REQUEST-HMAC"] = Api::Internal.request_hmac(Time.now, GitHub.reposd_hmac_key)
      end

      resp = if method == "HEAD"
        @reposd_client.head(
          path,
          params,
          request_headers
        )
      elsif method == "POST"
        request_headers["Content-Type"] ||= "application/json"
        @reposd_client.post(
          path,
          params,
          request_headers
        )
      elsif method == "DELETE"
        @reposd_client.delete(
          path,
          params,
          request_headers
        )
      else
        @reposd_client.get(
          path,
          params,
          request_headers
        )
      end

      resp
    rescue Faraday::Error => e
      Failbot.report(e, app: "github-reposd-client")
    end
  end
end
