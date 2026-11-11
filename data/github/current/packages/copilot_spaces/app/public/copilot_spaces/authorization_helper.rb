# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module AuthorizationHelper
    extend T::Helpers

    sig { params(user: User, cap_filter: ConditionalAccess::Filter).returns(T::Array[Organization]) }
    def self.authorized_orgs(user, cap_filter)
      organizations = if user.is_a?(Bot)
        # Bot#installation is aliased to #ability_delegate and may return either an
        # IntegrationInstallation (which defines #organization) or a
        # Scoped/SiteScopedIntegrationInstallation (which does NOT define #organization
        # but does expose #target). Use #target and check for an Organization to avoid
        # NoMethodError on scoped server-to-server installations.
        installation_target = user.installation&.target
        installation_target.is_a?(Organization) ? [installation_target] : []
      else
        user.organizations
      end

      cap_filter.authorized_resources(organizations)
    end
  end
end
