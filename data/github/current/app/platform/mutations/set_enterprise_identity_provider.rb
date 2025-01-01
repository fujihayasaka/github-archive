# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetEnterpriseIdentityProvider < Platform::Mutations::Base
      description "Creates or updates the identity provider for an enterprise."

      # This mutation can only be run by end-users in the Enterprise Cloud environment.
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set an identity provider.", required: true, loads: Objects::Enterprise
      argument :sso_url, Scalars::URI, "The URL endpoint for the identity provider's SAML SSO.", required: true
      argument :issuer, String, "The Issuer Entity ID for the SAML identity provider", required: false
      argument :idp_certificate, String, "The x509 certificate used by the identity provider to sign assertions and responses.", required: true
      argument :signature_method, Enums::SamlSignatureAlgorithm, "The signature algorithm used to sign SAML requests for the identity provider.", required: true
      argument :digest_method, Enums::SamlDigestAlgorithm, description: "The digest algorithm used to sign SAML requests for the identity provider.", required: true

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

        unless enterprise.owner?(actor)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set an identity provider on this enterprise.")
        end

        new_setup = enterprise.saml_provider.blank?
        provider = enterprise.saml_provider || enterprise.build_saml_provider
        provider.user_that_must_test_settings = actor
        attributes = inputs.slice \
          :sso_url, :issuer, :idp_certificate, :signature_method, :digest_method
        if provider.update(attributes)
          # Ensure that any possible cached setup flow values are cleared.
          flow = SamlProviderSetupFlow.new(enterprise)
          flow.clear_kv_values

          # Existing orgs with Team Sync enabled for their own provider will
          # misbehave (no UI to toggle Team Sync, membership losses upon team
          # mapping changes, etc.) when we add a provider to their Enterprise,
          # so we'd better disable on those orgs when adding a new config.
          #
          # (disabling removes mappings without touching memberships => 🏆)
          if new_setup
            TeamSync::Tenant.not_disabled.where(
              organization_id: enterprise.organization_ids,
            ).each(&:disable)
          end

          { identity_provider: provider }
        else
          raise Errors::Unprocessable.new(provider.errors.full_messages.join(", "))
        end
      end
    end
  end
end
