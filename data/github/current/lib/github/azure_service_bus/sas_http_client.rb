# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class SasHttpClient < HttpClient
      sig { params(connection_string: String).void }
      def initialize(connection_string:)
        @connection_string = T.let(connection_string, String)
        @connection_configuration = T.let(nil, T.nilable(ConnectionConfiguration))
        @signer = T.let(nil, T.nilable(SharedAccessSigner))
        super()
      end

      private

      sig { override.returns(String) }
      def host
        connection_configuration.default_host
      end

      sig { override.params(uri: URI::Generic).returns(T::Hash[String, String]) }
      def authentication_headers(uri)
        { "Authorization" => signer.authorization_token(uri) }
      end

      sig { returns(String) }
      attr_reader :connection_string

      sig { returns(ConnectionConfiguration) }
      def connection_configuration
        @connection_configuration ||= ConnectionConfiguration.from_connection_string(connection_string)
      end

      sig { returns(SharedAccessSigner) }
      def signer
        @signer ||= SharedAccessSigner.new(connection_configuration.sas_key_name, connection_configuration.sas_key)
      end
    end
  end
end
