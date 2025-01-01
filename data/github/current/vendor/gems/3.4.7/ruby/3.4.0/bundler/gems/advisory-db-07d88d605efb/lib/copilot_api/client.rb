# frozen_string_literal: true

require "rack"
require "uri"

module CopilotAPI
  class Client
    class Disabled < StandardError
      def initialize(message = nil)
        super(message || "advisorydb-predictor is not enabled")
      end
    end

    class UnknownFeature < StandardError
      def initialize(message = nil)
        super(message || "advisorydb-predictor unknown feature identifier")
      end
    end

    class Error < StandardError; end
    class EntityTooLargeError < Error; end
    class NetworkError < Error; end
    class RequestError < Error; end
    class RAIError < Error; end

    class RateLimitError < Error
      attr_reader :retry_after

      def initialize(msg = nil, retry_after:)
        super(msg)
        @retry_after = retry_after
      end
    end

    class NotFoundError < Error; end

    def self.enabled?
      false
    end

    def self.make_request(path:, method:, data: {})
      res = connection.send(method, path, data) do |req|
        req.headers[:copilot_integration_id] = AdvisoryDB::Config::Capi.capi_integration_id
        req.headers[:request_hmac] = generate_request_hmac(AdvisoryDB::Config::Capi.capi_secret)
      end
      handle_request_error(res)
      res
    # retries are handled by the job that calls make_prediction
    rescue Faraday::Error => error
      raise(NetworkError, error.message)
    end

    def self.handle_request_error(res)
      return if res.status == 200 || res.success?

      case res.status
      when 403
        raise(RAIError, "The response was filtered due to the content of the request. Please contact our support team.") if res.body == "content_filtered in response"

        raise(RequestError, res.body)
      when 404
        raise(NotFoundError, res.body)
      when 413
        raise(EntityTooLargeError, res.body)
      when 429
        raise RateLimitError.new(res.body, retry_after: res.headers&.[]("X-Ratelimit-User-Retry-After")&.to_f)
      when 400..499
        raise(RequestError, res.body)
      when 500
        raise(NetworkError, "server encountered an internal error (HTTP 500) with response: #{res.body}")
      else
        raise(NetworkError, "something unexpected happened. HTTP Status: #{res.status}")
      end
    end

    def self.generate_request_hmac(key)
      current = DateTime.now.strftime("%s")
      hmac_value = OpenSSL::HMAC.hexdigest("SHA256", key, current)
      "#{current}.#{hmac_value}"
    end

    def self.make_prediction(model:, messages:, max_tokens: 100, temperature: 0, stop: [])
      data = { model: model, messages: messages, max_tokens: max_tokens, temperature: temperature, stop: stop }
      make_request(
        path: AdvisoryDB::Config::Capi.chat_completion_url,
        method: :post,
        data: data,
      )
    end

    def self.connection
      @connection ||= Faraday.new do |faraday|
        faraday.request :json
        faraday.request :retry
        faraday.response :json
        faraday.adapter :net_http
      end
    end
  end
end
