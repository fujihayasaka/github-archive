# typed: strict
# frozen_string_literal: true

module GitHubFeCore
  class Client

    sig { void }
    def initialize
      @github_fe_core_client = T.let(GitHub::FaradayClient.internal("github_fe_core", GitHub.github_fe_core_url), Faraday::Connection)
    end

    sig { params(path: String, params: T.untyped, headers: T::Hash[String, T.untyped]).returns(Faraday::Response) }
    def internal_request(path:, params:, headers:)
      # Transform Rack env-style headers back into how request headers look. (_ replaced with - mostly)
      request_headers = headers.select { |key, _| key.start_with?("HTTP_") && key != "HTTP_HOST" }.transform_keys { |key| key.sub("HTTP_", "").upcase.gsub("_", "-") }

      # convert params like "include_hidden=true" into a hash
      params = URI.decode_www_form(params).to_h if params.is_a?(String)

      @github_fe_core_client.get(
        path,
        params,
        request_headers.merge({ "Request-HMAC" => ::Api::Internal.request_hmac(Time.now, GitHub.github_fe_core_hmac_key) })
      )
    rescue Faraday::Error => e
      Failbot.report(e, app: "github-fe-core-client")
    end
  end
end
