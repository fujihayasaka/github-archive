# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class HttpClient
      FailedRequestError = Class.new(StandardError)

      def initialize(connection_string:)
        @connection_string = connection_string
      end

      def make_request(method:, path:, query: Hash.new, body: nil, headers: Hash.new)
        uri = URI::HTTPS.build(host: connection_configuration.default_host, path: path, query: query.to_query)
        make_request_to_uri(method: method, uri: uri, body: body, headers: headers)
      end

      def make_request_to_uri(method:, uri:, body: nil, headers: Hash.new)
        response = connection.public_send(method, uri) do |request|
          request.body = body if body
          request.headers = headers.merge(
            "Authorization" => signer.authorization_token(request.path)
          )
        end

        raise FailedRequestError.new("Request failed (#{response.status})") if !response.success?
        response
      end

      private

      attr_reader :connection_string

      def connection
        @connection ||= Faraday.new do |builder|
          builder.request :retry, max: 3, methods: [:get, :post, :put, :delete], exceptions: [Faraday::Error]
          builder.adapter Faraday.default_adapter
        end
      end

      def connection_configuration
        @connection_configuration ||= ConnectionConfiguration.from_connection_string(connection_string)
      end

      def signer
        @signer ||= SharedAccessSigner.new(connection_configuration.sas_key_name, connection_configuration.sas_key)
      end
    end
  end
end
