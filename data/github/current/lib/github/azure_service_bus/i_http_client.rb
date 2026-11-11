# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    module IHttpClient
      extend T::Helpers

      interface!

      sig do
        abstract.params(
          method: Symbol,
          path: String,
          query: T::Hash[T.any(Symbol, String), T.untyped],
          body: T.nilable(String),
          headers: T::Hash[T.any(Symbol, String), String]
        ).returns(Faraday::Response)
      end
      def make_request(method:, path:, query: {}, body: nil, headers: {}); end

      sig do
        abstract.params(
          method: Symbol,
          uri: URI::Generic,
          body: T.nilable(String),
          headers: T::Hash[T.any(Symbol, String), String]
        ).returns(Faraday::Response)
      end
      def make_request_to_uri(method:, uri:, body: nil, headers: {}); end
    end
  end
end
