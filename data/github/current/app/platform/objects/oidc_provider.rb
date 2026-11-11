# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OIDCProvider < Platform::Objects::Base
      model_name "Business::OIDCProvider"
      description "An OIDC identity provider configured to provision identities for an enterprise. Visible to enterprise owners or enterprise owners' personal access tokens (classic) with read:enterprise or admin:enterprise scope."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["admin:enterprise"]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_target.then do |target|
          permission.access_allowed?(:site_admin_authorization, permission: :read_enterprise_sso, resource: target, repo: nil, organization: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # Let site admins view all identity providers
        return true if permission.viewer&.respond_to?(:site_admin?) && permission.viewer.site_admin?

        object.async_target.then do |target|
          Authz.domain.check_allowed(permission.viewer, :read_enterprise_sso, target)
        end
      end

      implements_node templates: [[:bop, :enterprise_id, :oidc_provider_id]], as: "OIDCP", ready_date: "1970-01-01" do |oidcp|
        {
          prefix: :bop,
          enterprise_id: oidcp.business_id,
          oidc_provider_id: oidcp.id,
        }
      end

      field :enterprise, Objects::Enterprise, method: :async_target, description: "The enterprise this identity provider belongs to.", null: true

      field :external_identities, resolver: Platform::Resolvers::ExternalIdentities, description: "ExternalIdentities provisioned by this identity provider.", connection: true

      field :provider_type, Enums::OIDCProviderType, description: "The OIDC identity provider type", null: false, method: :oidc_provider

      field :tenant_id, String, "The id of the tenant this provider is attached to", null: false
    end
  end
end
