# typed: true
# frozen_string_literal: true

module Platform
  module Authentication

    # The responsibility of this class is to accumulate the authentication state and user
    # properties from the Identity Provider, and create a Result and UserData class that
    # can be consumed by the callsite.
    #
    # The specific mapping rules, for instance from a specific Identity Provider's roles to
    # GitHub roles, or IdP group names to GitHub team or organizations, will be encapsulated
    # here.
    class SamlConsumer

      attr_reader :validation_properties

      # Create a new SamlConsumer instance.
      #
      # validation_properties - a hash of properties used to validate the SAML response.
      #
      #    The following values are required in validation_properties:
      #      issuer          - The URL of the SAML authority making the assertion (the IdP)
      #      sp_url          - The URL of the Service Provider requesting the authentication (the SP)
      #      idp_certificate - The certificate used to validate the signature of the response
      #
      def initialize(validation_properties)
        if validation_properties.key?(:encrypted_assertions) && validation_properties[:encrypted_assertions]
          @encryption_properties = validation_properties.extract!(:encrypted_assertions, :encryption_method, :key_transport_method, :key)
        end

        @persist_attributes = if validation_properties.key?(:persist_attributes)
          !!validation_properties.delete(:persist_attributes)
        else
          true
        end
        @validation_properties = validation_properties
      end

      # Public       - Perform the authentication request to the SAML IdP, retrieve user data & build the
      #                AuthResult & UserData objects to pass back to the caller.
      #
      # raw_response - The raw SAML Response XML
      # relay_state  - The value of the RelayState given by the IdP in the Response call
      #
      # Returns - GitHub::Authentication::Result
      def perform(raw_response)
        auth_result = consume(raw_response)

        if auth_result.success?
          auth_result.user_data = Platform::Provisioning::SamlUserData.load(
            auth_result.assertion,
            persist_attributes: @persist_attributes,
          )
        end

        auth_result
      end

      private

      # Private: Consume SAML Response XML and return a SamlStrategy::Result
      # object, wrapping the SAML assertion, indicating whether the AuthnRequest
      # was a success or failure.
      #
      # Returns an Orgs::IdentityManagement::SamlStrategy::Result object.
      def consume(response)
        begin
          assertion = ::SAML::Message::Response.from_param(response, @encryption_properties)
        rescue => err
          return Platform::Authentication::SamlResult.invalid(errors: err.message)
        end

        if assertion.valid?(validation_properties)
          if assertion.success?
            Platform::Authentication::SamlResult.authorized(assertion)
          else
            Platform::Authentication::SamlResult.unauthorized(assertion)
          end
        else
          Platform::Authentication::SamlResult.invalid(assertion)
        end
      end
    end
  end
end
