# typed: true
# frozen_string_literal: true

module Platform
  module Authentication
    class SamlAuthnRequestUrl
      AUTHN_REQUEST_TIMEOUT = 5.minutes

      # Used as the `RelayState` parameter.
      attr_accessor :relay_state

      # Public: Creates a SamlAuthnRequestUrl object
      #
      # options - Hash of required parameters to build the IdP URL:
      #           sp_url                          - A URL that uniquely identifies the Service Provider
      #           sso_url                         - The IdP URL
      #           issuer                          - Unique URL ID for the Identity Provider
      #           destination                     - The IdP URL (likely the same as sso_url)
      #           assertion_consumer_service_url  - The saml/consume endpoint that the IdP will post the result to
      #
      def initialize(options)
        @relay_state = options.delete(:relay_state)
        @options = options
      end

      # Public - returns the SAML AuthnRequest encoded as a URL String.
      def to_s
        idp_url = Addressable::URI.parse(options[:sso_url])

        idp_url.query_values = Hash(idp_url.query_values).merge({
          "SAMLRequest" => request.to_query,
          "RelayState"  => relay_state,
        })

        idp_url.to_s
      end

      # Public - returns the AuthnRequest message.
      def request
        @request ||= ::SAML::Message::AuthnRequest.new(options.merge(expiry: expiry))
      end

      # Public - returns the DateTime of the AuthnRequest expiry.
      def expiry
        @expiry ||= AUTHN_REQUEST_TIMEOUT.from_now
      end

      private

      attr_reader :options
    end
  end
end
