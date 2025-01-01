# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class HttpClient

      DEFAULT_TIMEOUT = 20
      CONTENT_TYPE = "application/json"

      def initialize(token_client: nil)
        @token_client = token_client
      end

      def send_request(method:, uri:, params: {}, headers: {}, body: nil, timeout: DEFAULT_TIMEOUT)
        response = connection.public_send(method, uri) do |request|
          request.options.timeout = timeout
          request.body = body
          request.headers["Accept"] = CONTENT_TYPE
          if @token_client
            request.headers["Authorization"] = bearer_token
          end
          request.params.merge!(params)
          request.headers.merge!(headers)
        end
        response
      end

      private

      def bearer_token
        "Bearer #{@token_client.token}"
      end

      def connection
        @connection ||= Faraday.new do |builder|
          builder.use ::GitHub::FaradayMiddleware::RaiseError
          builder.request :retry,
            methods: [:delete, :get, :head, :merge, :patch, :post, :put],
            retry_statuses: [408, 429, *500...600],
            exceptions: [Errno::ETIMEDOUT, "Timeout::Error", Faraday::TimeoutError, Faraday::RetriableResponse, Faraday::ConnectionFailed],
            interval: 0.05,
            interval_randomness: 0.5,
            backoff_factor: 2
          builder.request :json
          builder.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }
          builder.adapter Faraday.default_adapter
        end
      end
    end
  end
end
