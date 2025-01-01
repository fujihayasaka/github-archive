# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EnterpriseIdentityProvider < Platform::Objects::Base
      model_name "Business::SamlProvider"
      description "An identity provider configured to provision identities for an enterprise. Visible to enterprise owners or
        enterprise owners' personal access tokens (classic) with read:enterprise or admin:enterprise scope.".squish

      minimum_accepted_scopes ["read:enterprise"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_target.then do |target|
          if GitHub.enterprise?
            permission.access_allowed?(:view_enterprise_external_identities_read_only, resource: target, organization: nil, repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
          else
            permission.access_allowed?(
              :site_admin_authorization,
              permission: :read_enterprise_sso,
              resource: target,
              repo: nil,
              organization: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Let site admins view all identity providers
        return true if permission.viewer&.respond_to?(:site_admin?) && permission.viewer.site_admin?

        object.async_target.then do |target|
          if GitHub.enterprise?
            target.owner? permission.viewer
          else
            Authz.domain.check_allowed(permission.viewer, :read_enterprise_sso, target)
          end
        end
      end

      implements_node templates: [[:eeip, :enterprise_id, :enterprise_identity_provider_id]], as: "EIP", ready_date: "2021-05-15" do |eip|
        {
          prefix: :eeip,
          enterprise_id: eip.business_id,
          enterprise_identity_provider_id: eip.id,
        }
      end

      field :enterprise, Objects::Enterprise, method: :async_target, description: "The enterprise this identity provider belongs to.", null: true

      field :external_identities, resolver: Platform::Resolvers::ExternalIdentities, description: "ExternalIdentities provisioned by this identity provider.", connection: true

      field :sso_url, Scalars::URI, description: "The URL endpoint for the identity provider's SAML SSO.", null: true

      field :issuer, String, description: "The Issuer Entity ID for the SAML identity provider.", null: true

      field :idp_certificate, Scalars::X509Certificate, description: "The x509 certificate used by the identity provider to sign assertions and responses.", null: true

      field :signature_method, Enums::SamlSignatureAlgorithm, description: "The signature algorithm used to sign SAML requests for the identity provider.", null: true

      field :digest_method, Enums::SamlDigestAlgorithm, description: "The digest algorithm used to sign SAML requests for the identity provider.", null: true

      field :recovery_codes, [String], description: "Recovery codes that can be used by admins to access the enterprise if the identity provider is unavailable.", null: true

      def recovery_codes
        # Deliberately resolve using the version of the recovery codes formatted as "nnnnn-nnnnn"
        object.formatted_recovery_codes
      end

      field :provisioning_enabled, Boolean, visibility: :under_development, description: "Has user provisioning been enabled for the enterprise", null: false

      field :saml_deprovisioning_enabled, Boolean, visibility: :under_development, description: "Has SAML user deprovisioning been enabled for the enterprise", null: false
    end
  end
end
