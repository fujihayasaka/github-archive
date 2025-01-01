# typed: true
# frozen_string_literal: true

class McpOauth::HttpClient
  def self.get(url)
    faraday.get(url)
  end

  def self.post(url, body, content_type: "application/json", authorization: nil)
    faraday.post do |req|
      req.url url
      req.headers["Content-Type"] = content_type
      req.headers["Authorization"] = authorization if authorization
      req.body = content_type == "application/json" ? body.to_json : URI.encode_www_form(body)
    end
  end

  def self.faraday
    GitHub::FaradayClient::External.new { |c| c.adapter Faraday.default_adapter }
  end

  private_class_method :faraday
end
