# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class AadHttpClient < HttpClient
      sig { params(namespace: String, token_provider: GitHub::Azure::ApplicationTokenProvider).void }
      def initialize(namespace:, token_provider:)
        super()
        @namespace = T.let(namespace, String)
        @token_provider = T.let(token_provider, GitHub::Azure::ApplicationTokenProvider)
      end

      private

      sig { override.returns(String) }
      def host
        "#{namespace}.servicebus.windows.net"
      end

      sig { override.params(uri: URI::Generic).returns(T::Hash[String, String]) }
      def authentication_headers(uri)
        { "Authorization" => token_provider.get_authentication_header }
      end

      sig { returns(String) }
      attr_reader :namespace

      sig { returns(GitHub::Azure::ApplicationTokenProvider) }
      attr_reader :token_provider
    end
  end
end
