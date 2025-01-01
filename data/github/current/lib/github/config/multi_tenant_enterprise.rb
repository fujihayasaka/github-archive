# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    # Mixin for the GitHub module that contains all configuration settings
    # related to GitHub Multi-Tenant.
    module MultiTenantEnterprise
      # Is the application running in multi-tenant enterprise mode?
      #
      # Returns boolean
      def multi_tenant_enterprise?
        return @multi_tenant_enterprise if defined?(@multi_tenant_enterprise)
        @multi_tenant_enterprise = GitHub.runtime.multi_tenant_enterprise_environment?
      end
      attr_writer :multi_tenant_enterprise

      # Are organizations scoped to the owning business?
      # Includes org name and business id
      #
      # Returns true in multi tenant mode.
      # Returns false in all other environments.
      def organization_namespacing_enabled?
        multi_tenant_enterprise?
      end

      # Does the environment or runtime permit validation checks on the business id?
      def multi_tenant_business_id?
        !Rails.env.production? || GitHub.multi_tenant_enterprise?
      end
    end
  end

  extend Config::MultiTenantEnterprise
end
