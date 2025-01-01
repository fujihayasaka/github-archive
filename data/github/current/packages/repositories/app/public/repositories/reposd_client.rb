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

    sig { params(path: String, params: T.untyped, headers: T.untyped).returns(T.untyped) }
    def api_request(path:, params:, headers:)
      request_headers = headers.select { |key, _| key.start_with?("HTTP_") && key != "HTTP_HOST" }.transform_keys { |key| key.sub("HTTP_", "").upcase.gsub("_", "-") }

      # convert params like "ref=master" into a hash
      params = URI.decode_www_form(params).to_h if params.is_a?(String)

      resp = @reposd_client.get(
        path,
        params,
        request_headers.merge({ "Request-HMAC" => Api::Internal.request_hmac(Time.now, GitHub.reposd_hmac_key) })
      )

      resp
    rescue Faraday::Error => e
      Failbot.report(e, app: "github-reposd-client")
    end
  end
end
