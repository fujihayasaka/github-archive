# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationIdentityProvider < Platform::Objects::Base
      model_name "Organization::SamlProvider"
      description "An Identity Provider configured to provision SAML and SCIM identities for Organizations.
        Visible to (1) organization owners, (2) organization owners' personal access tokens (classic) with read:org or admin:org scope,
        (3) GitHub App with an installation token with read or write access to members.".squish

      implements_node templates: [[:ooip, :organization_id, :organization_identity_provider_id]], as: "OIP", ready_date: "2021-06-18" do |organization_identity_provider|
        {
          prefix: :ooip,
          organization_id: organization_identity_provider.organization_id,
          organization_identity_provider_id: organization_identity_provider.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        object.async_target.then do |org|
          permission.access_allowed?(:view_org_identity_provider, resource: org, organization: org, current_repo: nil, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_target.then do |organization|
          organization.async_adminable_by?(permission.viewer).then do |adminable|
            next true if adminable
            next false unless permission.viewer.try(:installation)
            next true if organization.resources.members.readable_by?(permission.viewer)
            next true if organization.resources.organization_administration.readable_by?(permission.viewer)
            false
          end
        end
      end

      minimum_accepted_scopes ["read:org"]

      field :organization, Objects::Organization, method: :async_target, description: "Organization this Identity Provider belongs to", null: true

      field :external_identities, resolver: Platform::Resolvers::ExternalIdentities, description: "External Identities provisioned by this Identity Provider", connection: true

      field :sso_url, Scalars::URI, description: "The URL endpoint for the Identity Provider's SAML SSO.", null: true

      field :issuer, String, description: "The Issuer Entity ID for the SAML Identity Provider", null: true

      field :idp_certificate, Scalars::X509Certificate, description: "The x509 certificate used by the Identity Provider to sign assertions and responses.", null: true

      # http://www.datypic.com/sc/ds/e-ds_SignatureMethod.html
      field :signature_method, Scalars::URI, description: "The signature algorithm used to sign SAML requests for the Identity Provider.", null: true

      # http://www.datypic.com/sc/ds/e-ds_DigestMethod.html
      field :digest_method, Scalars::URI, description: "The digest algorithm used to sign SAML requests for the Identity Provider.", null: true
    end
  end
end
