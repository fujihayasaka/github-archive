# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class HttpClient
      include IHttpClient

      extend T::Helpers

      abstract!

      FailedRequestError = Class.new(StandardError)

      sig { void }
      def initialize
        @connection = T.let(nil, T.nilable(Faraday::Connection))
      end

      sig do
        override.params(
          method: Symbol,
          path: String,
          query: T::Hash[T.any(Symbol, String), T.untyped],
          body: T.nilable(String),
          headers: T::Hash[T.any(Symbol, String), String]
        ).returns(Faraday::Response)
      end
      def make_request(method:, path:, query: {}, body: nil, headers: {})
        uri = URI::HTTPS.build(host: host, path: path, query: query.to_query)
        make_request_to_uri(method: method, uri: uri, body: body, headers: headers)
      end

      sig do
        override.params(
          method: Symbol,
          uri: URI::Generic,
          body: T.nilable(String),
          headers: T::Hash[T.any(Symbol, String), String]
        ).returns(Faraday::Response)
      end
      def make_request_to_uri(method:, uri:, body: nil, headers: {})
        auth_headers = authentication_headers(uri)
        response = connection.public_send(method, uri) do |request|
          request.body = body if body
          request.headers = headers.merge(auth_headers)
        end

        raise FailedRequestError.new("Request failed (#{response.status})") if !response.success?
        response
      end

      private

      sig { returns(Faraday::Connection) }
      def connection
        @connection ||= GitHub::FaradayClient::External.new do |builder|
          builder.request :retry, max: 3, methods: [:get, :post, :put, :delete], exceptions: [Faraday::Error]
          builder.adapter Faraday.default_adapter
        end
      end

      # Abstract methods that subclasses must implement
      sig { abstract.returns(String) }
      def host; end

      sig { abstract.params(uri: URI::Generic).returns(T::Hash[String, String]) }
      def authentication_headers(uri); end
    end
  end
end
