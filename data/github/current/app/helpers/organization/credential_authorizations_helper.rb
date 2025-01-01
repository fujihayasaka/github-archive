# typed: strict
# frozen_string_literal: true

module Organization::CredentialAuthorizationsHelper
  sig { params(credential: T.any(OauthAccessTokens::IOauthAccess, PublicKey)).returns(T::Hash[Organization, T.any(NilClass, Organization::CredentialAuthorization)]) }
  def organization_credential_authorization_map(credential)
    actor = credential.user
    return {} unless actor

    org_credential_map = {}
    sso_organizations = Organization::CredentialAuthorization.available_organizations(actor)

    sso_organizations.select(:id, :login, :display_login).find_in_batches do |orgs|
      # Every organization needs to be listed.
      orgs.each { |org| org_credential_map[org] = nil }

      preloaded_credential_authorizations = Organization::CredentialAuthorization.
        where(credential: credential, organization: orgs).
        includes(:revoked_by, organization: [
          {
            business_membership: {
              business: [:saml_provider, :configuration_entries]
            }
          },
          :configuration_entries
        ])

      preloaded_credential_authorizations.each do |credential_authorization|
        org_credential_map[credential_authorization.organization] = credential_authorization
      end
    end

    org_credential_map
  end

  sig { params(credential: T.any(OauthAccessTokens::IOauthAccess, PublicKey)).returns(T::Hash[Organization, T.any(NilClass, Organization::CredentialAuthorization)]) }
  def organization_credential_authorization_map_with_tracing(credential)
    GitHub.tracer.in_span("Organization::CredentialAuthorizationsHelper#organization_credential_authorization_map", kind: :internal, attributes: {
      "gh.oauth_access.id" => credential.id,
    }) do |_|
      actor = credential.user
      return {} unless actor

      org_credential_map = {}
      sso_organizations = GitHub.tracer.in_span("load sso organization", kind: :internal) do |_|
        Organization::CredentialAuthorization.available_organizations(actor)
      end

      GitHub.tracer.in_span("preload sso organizations", kind: :internal) do |_|
        sso_organizations.select(:id, :login, :display_login).find_in_batches do |orgs|
          GitHub.tracer.in_span("preload batch", kind: :internal, attributes: {
            "gh.organizations.count" => orgs.count,
          }) do |_|
            # Every organization needs to be listed.
            orgs.each { |org| org_credential_map[org] = nil }

            preloaded_credential_authorizations = Organization::CredentialAuthorization.
               where(credential: credential, organization: orgs).
               includes(:revoked_by, organization: [
                 {
                   business_membership: {
                     business: [:saml_provider, :configuration_entries]
                   }
                 },
                 :configuration_entries
               ])

            preloaded_credential_authorizations.each do |credential_authorization|
              org_credential_map[credential_authorization.organization] = credential_authorization
            end
          end
        end
      end

      org_credential_map
    end
  end

  # Internal: Determine if the user has any organizations that have SAML
  # protection.
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def show_sso_ready_badge?
    return @show_sso_ready_badge if defined?(@show_sso_ready_badge)
    @show_sso_ready_badge = T.let(Organization::CredentialAuthorization.available_organizations(T.unsafe(self).current_user).exists?, T.untyped)
  end
end
