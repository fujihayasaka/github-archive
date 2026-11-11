# typed: strict
# frozen_string_literal: true

module FilterProviders::Helpers::OrganizationSuggestionsPayloadHelper
  sig { params(orgs: T::Array[Organization]).returns(OrganizationSuggestionsPayload) }
  def organization_suggestions_payload(orgs)
    { organizations: orgs.map { |org| organization_payload(org) } }
  end

  sig { params(org: Organization).returns(OrganizationPayload) }
  def organization_payload(org)
    {
      name: org.safe_profile_name,
      login: org.display_login,
      avatarUrl: org.primary_avatar_url(60),
    }
  end

  OrganizationSuggestionsPayload = T.type_alias do
    {
      organizations: T::Array[OrganizationPayload]
    }
  end

  OrganizationPayload = T.type_alias do
    {
      name: String,
      login: String,
      avatarUrl: String,
    }
  end
end
