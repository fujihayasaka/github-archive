# typed: strict
# frozen_string_literal: true

module Repositories
  class ReposdClient

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

    sig { params(path: String, params: T.untyped, headers: T.untyped, method: T.untyped, enable_reverse_proxy: T::Boolean).returns(T.untyped) }
    def api_request(path:, params:, headers:, method:, enable_reverse_proxy: false)
      request_headers = headers.select { |key, _| key.start_with?("HTTP_") && key != "HTTP_HOST" }.transform_keys { |key| key.sub("HTTP_", "").upcase.gsub("_", "-") }

      request_headers["X-Reposd-Should-Proxy"] = enable_reverse_proxy.to_s
      if enable_reverse_proxy
        if request_headers["ACCEPT-ENCODING"]&.include?("gzip")
          request_headers.delete("ACCEPT-ENCODING")
        end
      end

      # convert params like "ref=master" into a hash
      params = URI.decode_www_form(params).to_h if params.is_a?(String)

      resp = if method == "HEAD"
        @reposd_client.head(
          path,
          params,
          request_headers.merge({ "Request-HMAC" => Api::Internal.request_hmac(Time.now, GitHub.reposd_hmac_key) })
        )
      else
        @reposd_client.get(
          path,
          params,
          request_headers.merge({ "Request-HMAC" => Api::Internal.request_hmac(Time.now, GitHub.reposd_hmac_key) })
        )
      end

      resp
    rescue Faraday::Error => e
      Failbot.report(e, app: "github-reposd-client")
    end
  end
end
