# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetEnterpriseUserProvisioningSettings < Platform::Mutations::Base
      description "Updates the user provisioning settings for an enterprise."

      visibility :under_development

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to update user provisioning settings.", required: true, loads: Objects::Enterprise
      argument :provisioning_enabled, Boolean, "Enable automatic user provisioning for the enterprise?", required: true
      argument :saml_deprovisioning_enabled, Boolean, "Enable automatic SAML user deprovisioning for the enterprise?", required: true

      field :identity_provider, Objects::EnterpriseIdentityProvider, "The identity provider for the enterprise.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        actor = context[:actor]
        viewer = context[:viewer]
        provider = enterprise.saml_provider

        unless ::FeatureFlag.vexi.enabled?(:enterprise_idp_provisioning, enterprise, default: false)
          raise Platform::Errors::NotFound.new("Could not resolve to an Enterprise with the ID '#{enterprise.id}'.")
        end

        unless enterprise.owner?(actor)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to update user provisioning settings on this enterprise.")
        end

        unless enterprise.saml_provider
          raise Errors::Forbidden.new("#{enterprise} has no SAML provider configured.")
        end

        attributes = inputs.slice \
          :provisioning_enabled,
          :saml_deprovisioning_enabled

        if provider.update(attributes)
          { identity_provider: provider }
        else
          raise Errors::Unprocessable.new(provider.errors.full_messages.join(", "))
        end
      end
    end
  end
end
