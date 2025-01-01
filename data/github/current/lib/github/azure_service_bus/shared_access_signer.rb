# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class SharedAccessSigner
      EXPIRE_IN = 5.minutes
      NAME = "SharedAccessSignature"

      def initialize(key_name, key)
        @key_name = key_name
        @key = key
      end

      # See https://docs.microsoft.com/en-us/azure/service-bus-messaging/service-bus-sas for documentation
      # on this format of token
      def authorization_token(uri)
        url_encoded_resource = URI.encode_www_form_component(uri.to_s.downcase)
        expiry = EXPIRE_IN.from_now.to_i
        signature = URI.encode_www_form_component(signature(url_encoded_resource, expiry))

        "#{NAME} sig=#{signature}&se=#{expiry}&skn=#{key_name}&sr=#{url_encoded_resource}"
      end

      private

      attr_reader :key_name, :key

      def signature(url_encoded_resource, expiry)
        signed = OpenSSL::HMAC.digest("sha256", key, [url_encoded_resource, expiry].join("\n"))
        Base64.strict_encode64(signed)
      end
    end
  end
end
