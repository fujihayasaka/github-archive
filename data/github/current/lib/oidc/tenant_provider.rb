# typed: true
# frozen_string_literal: true

require "date"
require "securerandom"
require "oidc"

module OIDC
  class TenantProvider

    class TenantProviderError < StandardError; end
    class MissingOIDCProviderKeyError < TenantProviderError; end
    class InvalidCommonProviderConfigurationError < TenantProviderError; end
    class InvalidTenantProviderConfigurationError < TenantProviderError; end

    attr_reader :business_id, :oidc_provider_key

    # The TenantProvider is a wrapper around the Business::OIDCProvider
    # and the IdP configurations for a businesses and is used to interface with the OIDCAuth strategy.
    #
    # @params business          - Business to look up the Business::OIDCProvider.
    # @params oidc_provider_key - If there is no saved Business::OIDCProvider for business_id,
    #                             initialize a TenantProvider with just the common configuration
    #                             info for the corresponding provider.
    #                             Should be one of Business::OIDCProvider.oidc_provider.keys
    #                             example: :azure, :okta
    def initialize(business, oidc_provider_key: nil)
      @oidc_provider = business&.oidc_provider
      @oidc_provider_key = @oidc_provider&.oidc_provider || oidc_provider_key

      raise MissingOIDCProviderKeyError, "No OIDC provider key for business_id #{business_id}" unless @oidc_provider_key.present?
    end

    #  Public: This is a client ID of a multi-tenant
    #  application that needs to be created in a GitHub tenant.
    #  Clients will have to authorize this application to allow access.
    def client_id
      GitHub.oidc_providers[@oidc_provider_key][:client_id]
    end

    # The tenant_id of the Business::OIDCProvider
    def tenant_id
      @oidc_provider&.tenant_id
    end

    # The OpenId Connect congfiguration associated to @oidc_provider
    # If the provider is populated, return the configuration with the tenanted endpoints
    # If the provider is nil, return the configuration with the common endpoints
    #
    # Why not always use the common configuration? In cases where the user is a guest
    # in the identity provider tenant, we must call the endpoints with the specific tenant_id
    # that is attached to this business.
    # The default for the common endpoint is to auth against the home tenant of the user.
    # When the user is member of an EMU enterprise but a guest in the IdP tenant, we need
    # to auth against the specific tenant for the enterprise, not the home tenant of the user.
    #
    # Returns OIDC::Configuration
    def configuration
      tenant_id ? tenant_config : common_config
    end

    private

    # Returns the OIDC::Configuration for the @oidc_provider_key with the common endpoints
    def common_config
      return @common_config if defined?(@common_config)

      common_config = OIDC::Cache.get_configuration(@oidc_provider_key)
      raise InvalidCommonProviderConfigurationError, "Common configuration for provider is not valid" unless common_config.valid?
      @common_config = common_config
    end

    # Returns the OIDC::Configuration for the @oidc_provider_key with endpoints including the specific tenant_id
    def tenant_config
      return @tenant_config if defined?(@tenant_config)

      tenant_config = OIDC::Cache.get_configuration(@oidc_provider_key, tenant_id)
      raise InvalidTenantProviderConfigurationError, "Tenant configuration for provider is not valid" unless tenant_config.valid?
      @tenant_config = tenant_config
    end
  end
end
