# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationProgrammaticAccessGrantDependency
  extend T::Helpers
  include GranularPermissionsHelper

  requires_ancestor { T.class_of(Api::Serializer) }

  def org_pat_grant_hash(grant, options = {})
    access = grant.user_programmatic_access
    token_expiration = ProgrammaticAccessToken.expiration_for(access).value
    expired = false

    if token_expiration == :expired
      expired = true
      token_expiration = nil
    end

    {
      # We're exposing the grant ID here, but we describe it as the "fine-grained personal access token ID" in the docs.
      id: grant.id,
      owner: simple_user_hash(access.owner, content_options(options)),
      repository_selection: grant.repository_selection,
      repositories_url: url("/organizations/#{grant.organization_id}/personal-access-tokens/#{grant.id}/repositories"),
      permissions: permissions_by_subject_type_hash(grant.permissions),
      access_granted_at: grant.created_at.iso8601,
      token_expired: expired,
      token_expires_at: token_expiration&.iso8601,
      token_last_used_at: access.accessed_at&.iso8601,
    }
  end
end
