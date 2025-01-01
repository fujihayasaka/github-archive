# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RegenerateEnterpriseIdentityProviderRecoveryCodes < Platform::Mutations::Base
      description "Regenerates the identity provider recovery codes for an enterprise"

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set an identity provider.", required: true, loads: Objects::Enterprise

      field :identity_provider, Objects::EnterpriseIdentityProvider, "The identity provider for the enterprise.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :site_admin_authorization,
          permission: :write_enterprise_sso,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: true,
          allow_user_via_granular_actor: true,
        )
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        actor = context[:actor]
        viewer = context[:viewer]
        unless Authz.domain.check_allowed(actor, :write_enterprise_sso, enterprise)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to regenerate the identity provider recovery codes for this enterprise account.")
        end

        provider = enterprise.saml_provider
        if provider.present?
          provider.generate_recovery!
          if provider.save
            { identity_provider: provider }
          else
            raise Errors::Unprocessable.new(provider.errors.full_messages.join(", "))
          end
        else
          raise Errors::Unprocessable.new("This enterprise account does not have an identity provider set.")
        end
      end
    end
  end
end
