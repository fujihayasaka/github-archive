# typed: true
# frozen_string_literal: true

module Bing
  class UrlSubmissionClient
    def submit(urls)
      submission_path = "/indexnow"

      response = connection.post(submission_path) do |req|
        req.body = build_body(urls)
      end
    end

    private

    def build_body(urls)
      { "host": GitHub.url, "urlList": urls, "key": GitHub.bing_indexnow_api_key  }.to_json
    end

    def connection
      base_url = "https://www.bing.com"

      Faraday.new(
        url: base_url,
        params: nil,
        headers: { "Content-Type" => "application/json" }
      ) do |faraday|
        faraday.use GitHub::FaradayMiddleware::RaiseError
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
