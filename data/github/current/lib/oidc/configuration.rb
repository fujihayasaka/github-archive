# typed: true
# frozen_string_literal: true

# This is a class that represent configuration received from an IdP endpoint.
module OIDC
  class Configuration
    COMMON = "common"
    TENANT_ID = "{tenantid}"
    ISSUER = "issuer"
    AUTHORIZATION_ENDPOINT = "authorization_endpoint"
    TOKEN_ENDPOINT = "token_endpoint"
    JWKS_URI = "jwks_uri"
    ID_TOKEN_SIGNING_ALG_VALUES_SUPPORTED = "id_token_signing_alg_values_supported"

    # Public: initialize configuration
    def initialize(configuration, endpoint = COMMON, error: nil)
      @configuration = configuration
      @valid = error.blank?
      @endpoint = endpoint
    end

    # Public: Checks if the parsing of JSON was correct
    #
    # Return Boolean
    def valid?
      @valid
    end

    # Public: Get the authorization endpoint from the configuration
    #
    # Return String
    def authorization_endpoint
      return @authorization_endpoint if defined?(@authorization_endpoint)

      @authorization_endpoint = substitute_tenant(AUTHORIZATION_ENDPOINT, COMMON)
    end

    # Public: Get the token endpoint from the configuration
    #
    # Return String
    def token_endpoint
      return @token_endpoint if defined?(@token_endpoint)

      @token_endpoint = substitute_tenant(TOKEN_ENDPOINT, COMMON)
    end

    # Public: Get the signing keys endpoint from the configuration
    #
    # Return String
    def signing_keys_endpoint
      return nil unless valid?

      @configuration[JWKS_URI]
    end

    # Public: Get the signing key algorithm for token validation from the configuration
    #
    # Return Array
    def token_signing_alg_values
      return nil unless valid?

      @configuration[ID_TOKEN_SIGNING_ALG_VALUES_SUPPORTED]
    end

    # Public: Get the issuer from the configuration
    #
    # Return String
    def issuer
      return @issuer if defined?(@issuer)

      @issuer = substitute_tenant(ISSUER, TENANT_ID)
    end

    private

    # Private: Substitute tenant id for the common endpoint
    #
    # name - name of the configuration value
    #
    # Return String
    def substitute_tenant(name, sub_value)
      return nil unless valid?

      if @endpoint == COMMON
        @configuration[name]
      else
        @configuration[name].sub(sub_value, @endpoint)
      end
    end
  end
end
