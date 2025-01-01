
# typed: true
# frozen_string_literal: true

# This helper gets mixed into a controller to provide an array of SSO orgs to a React partial.
# CopilotChatService uses this list to determine if the current user's signed in SSO orgs have changed,
# signaling that it needs to generate a new auth token.
module CopilotAuthHelper
  extend T::Sig
  extend T::Helpers
  include GitHub::Memoizer

  abstract!

  sig { abstract.returns(Platform::Authorization::SAML) }
  def saml_for_user; end

  private

  sig { returns(T::Array[T::Hash[String, String]]) }
  memoize def sso_organizations
    orgs = Organization.where(id: saml_for_user.protected_organization_ids)

    orgs.map do |org|
      {
        id: org.id.to_s,
        login: org.display_login,
        avatarUrl: org.primary_avatar_url
      }
    end
  end
end
