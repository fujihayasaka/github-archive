# typed: strict
# frozen_string_literal: true

module PullRequests
  class PullsdClient
    include GitHub::Memoizer

    sig do
      params(
        pullsd_url: T.nilable(String),
        hmac_key: T.nilable(String)
      ).void
    end
    def initialize(pullsd_url: GitHub.pullsd_url, hmac_key: GitHub.pullsd_hmac_key)
      @pullsd_url = T.let(T.must(pullsd_url), String)
      @hmac_key = T.let(T.must(hmac_key), String)
    end

    sig { returns(Faraday::Connection) }
    memoize def connection
      GitHub::FaradayClient.internal("pullsd", @pullsd_url)
    end

    sig do
      params(
        path: String,
        params: T.any(String, T::Hash[String, T.untyped]),
        headers: T::Hash[String, String]
      )
      .returns(T.nilable(Faraday::Response))
    end
    def api_request(path:, params:, headers:)
      request_headers = sanitize_headers(headers:)

      # convert url params like "key=val" into a hash
      params = URI.decode_www_form(params).to_h if params.is_a?(String)

      resp = connection.get(
        path,
        params,
        request_headers.merge({ "Request-HMAC" => Api::Internal.request_hmac(Time.now, @hmac_key) })
      )

      resp
    rescue Faraday::Error => e
      Failbot.report(e, app: "github-pullsd-client")
    end

    private

    sig { params(headers: T::Hash[String, String]).returns(T::Hash[String, String]) }
    def sanitize_headers(headers:)
      headers
        .select { _1.start_with?("HTTP_") && _1 != "HTTP_HOST" }
        .transform_keys { _1.sub("HTTP_", "").upcase.gsub("_", "-") }
    end
  end
end
