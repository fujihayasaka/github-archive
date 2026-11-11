# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class SharedAccessSigner
      EXPIRE_IN = T.let(5.minutes, ActiveSupport::Duration)
      NAME = T.let("SharedAccessSignature", String)

      sig { params(key_name: String, key: String).void }
      def initialize(key_name, key)
        @key_name = T.let(key_name, String)
        @key = T.let(key, String)
      end

      # See https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-sas for documentation
      # on this format of token
      sig { params(uri: T.any(String, URI::Generic)).returns(String) }
      def authorization_token(uri)
        url_encoded_resource = URI.encode_www_form_component(uri.to_s.downcase)
        expiry = EXPIRE_IN.from_now.to_i
        signature = URI.encode_www_form_component(signature(url_encoded_resource, expiry))

        "#{NAME} sig=#{signature}&se=#{expiry}&skn=#{key_name}&sr=#{url_encoded_resource}"
      end

      private

      sig { returns(String) }
      attr_reader :key_name, :key

      sig { params(url_encoded_resource: String, expiry: Integer).returns(String) }
      def signature(url_encoded_resource, expiry)
        signed = OpenSSL::HMAC.digest("sha256", key, [url_encoded_resource, expiry].join("\n"))
        Base64.strict_encode64(signed)
      end
    end
  end
end
