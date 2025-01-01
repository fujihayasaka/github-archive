# typed: true
# frozen_string_literal: true

module ConditionalAccess::AuthzdActor
  def authzd_cap_actor
    Kernel.raise("authzd_cap_actor must be implemented in including types")
  end

  def authzd_cap_actor_attributes
    attrs = {}

    if a = authzd_cap_actor
      case a
      when Integration
        attrs["actor.id"] = a.id
        attrs["actor.type"] = a.class.name
        attrs["credential.type"] = "IntegrationToken"
        attrs["application.id"] = a.id
        attrs["application.owner.id"] = a.owner_id
        attrs["application.owner.type"] = a.owner_type == "User" ? a.async_owner.sync.type : a.owner_type
      when OauthApplication
        attrs["actor.id"] = a.id
        attrs["actor.type"] = a.class.name
        attrs["credential.type"] = "OauthAppClientSecret"
        attrs["application.id"] = a.id
        attrs["application.owner.id"] = a.user_id
        attrs["application.owner.type"] = a.async_user.sync&.type
      when Bot
        attrs["actor.id"] = a.id
        attrs["actor.type"] = a.class.name
        attrs["credential.type"] = "ServerToServerToken"
        GitHub::PrefillAssociations.prefill_associations(a, { integration: :owner })
        if integration = a.integration
          attrs["application.id"] = integration.id
          attrs["application.owner.id"] = integration.owner_id
          if integration.owner_type == "User"
            attrs["application.owner.type"] = integration.owner&.type
          else
            attrs["application.owner.type"] = integration.owner_type
          end
        end
        if installation = a.installation
          attrs["installation.id"] = installation.id
          attrs["installation.target.id"] = installation.target_id
          attrs["installation.target.type"] = installation.target_type == "User" ? installation.async_target.sync&.type : installation.target_type
        end
      when GitAuth::SSHKey, PublicKey
        if a.repository_id
          attrs["actor.id"] = a.repository_id
          attrs["actor.type"] = "Repository"
        else
          attrs["actor.id"] = a.user_id
          attrs["actor.type"] = "User"
        end
        attrs["credential.type"] = "SSHPublicKey"
        attrs["credential.id"] = a.id
      when GitHub::Authentication::SignedAuthToken
        attrs["actor.id"] = a.user.id
        # CAPTODO: the actor type can also be a Bot, but Authnd doesn't support that yet
        # The only Policy to use that Actor is SAML and it will return :inapplicable as soon as it detects
        # that there is a SAT, ignoring the Actor Type
        attrs["actor.type"] = "User"
        attrs["credential.type"] = "SignedAuthToken"
        # The version is a symbol, but it needs to be an int
        # Direct symbol to int conversion is not allowed in ruby
        # is there a better way?
        attrs["credential.version"] = a.version.to_s.to_i
        attrs["credential.expires_at_utc"] = a.expires.utc
        attrs["session.id"] = a.session&.id || 0
      when Mannequin
        attrs["actor.id"] = a.id
        attrs["actor.type"] = a.class.name
      when User
        attrs["actor.id"] = a.id
        attrs["actor.type"] = a.class.name
        if a.using_personal_access_token?
          attrs["credential.type"] = "PersonalAccessToken"
          attrs["credential.id"] = a.oauth_access.id
          attrs["credential.created_at_utc"] = a.oauth_access.created_at.utc
          attrs["credential.issued_at_utc"] = a.oauth_access.issued_at&.utc
          attrs["credential.expires_at_utc"] = a.oauth_access.expires_at&.utc
          attrs["credential.scopes"] = a.oauth_access.scopes
        elsif a.using_auth_via_user_programmatic_access?
          attrs["credential.type"] = "ProgrammaticAccessToken"
          attrs["access.id"] = a.programmatic_access.id
          attrs["credential.created_at_utc"] = a.programmatic_access.created_at.utc
          attrs["credential.issued_at_utc"] = a.programmatic_access.issued_at&.utc
          attrs["credential.expires_at_utc"] = a.programmatic_access.expires_at&.utc
        elsif a.using_auth_via_integration?
          attrs["credential.type"] = "UserToServerToken"
          attrs["credential.id"] = a.oauth_access.id
          attrs["application.id"] = a.oauth_access.application.id
          attrs["application.owner.id"] = a.oauth_access.application.owner_id
          attrs["application.owner.type"] = a.oauth_access.application.owner_type == "User" ? a.oauth_access.application.async_owner.sync.type : a.oauth_access.application.owner_type
        elsif a.using_auth_via_oauth_application?
          attrs["credential.type"] = "OAuthApplicationToken"
          attrs["credential.id"] = a.oauth_access.id
          attrs["application.id"] = a.oauth_access.application.id
          attrs["application.owner.id"] = a.oauth_access.application.user_id
          attrs["application.owner.type"] = a.oauth_access.application.async_user.sync&.type
          attrs["credential.scopes"] = a.oauth_access.scopes
        elsif a.using_auth_via_signed_auth_token?
          attrs["credential.type"] = "SignedAuthToken"
          token = a.sat_context
          attrs["credential.expires_at_utc"] = token.expires.utc
          if token.is_a?(GitHub::Authentication::GitAuth::SignedAuthToken)
            attrs["credential.version"] = "nil"
            attrs["session.id"] = 0
          elsif token.is_a?(GitHub::Authentication::SignedAuthToken)
            attrs["credential.version"] = token.version&.to_s
            attrs["session.id"] = token.session&.id || 0
          end
        end
      end
    end

    attrs
  end
end
