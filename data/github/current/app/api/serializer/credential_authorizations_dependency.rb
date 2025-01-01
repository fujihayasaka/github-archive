# typed: false
# frozen_string_literal: true

module Api::Serializer::CredentialAuthorizationsDependency
  def credential_authorizations_hash(credential_auth, options = {})
    credential_type_display_map = {
      "OauthAccess" => "personal access token",
      "PublicKey" => "SSH key",
    }

    hash = {
      login: credential_auth.actor&.login_for_api(use: options[:serialize_login]),
      credential_id: credential_auth.id,
      credential_type: credential_type_display_map[credential_auth.credential_type],
      credential_authorized_at: time(credential_auth.created_at),
      credential_accessed_at: time(credential_auth.accessed_at),
      authorized_credential_id: credential_auth.credential_id
    }

    # need these lonely operators here b/c credential's can become orphaned.
    if credential_auth.credential_type == "OauthAccess"
      hash[:token_last_eight] = credential_auth&.credential&.token_last_eight
      hash[:scopes] = credential_auth&.credential&.scopes
      hash[:authorized_credential_note] = credential_auth&.credential&.description
      hash[:authorized_credential_expires_at] = credential_auth&.credential&.expires_at
      if credential_auth&.organization&.feature_flag_enabled_or_raise?(:org_credential_authorizations_api_all_oauth_tokens) || credential_auth&.organization&.business&.feature_flag_enabled_or_raise?(:org_credential_authorizations_api_all_oauth_tokens) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        if credential_auth&.organization&.feature_flag_enabled?(:org_credential_authorizations_api_app_names, default: true)
          hash[:application_name] = credential_auth&.credential&.application&.name
          hash[:application_client_id] = credential_auth&.credential&.application&.key
        end
        case credential_auth&.credential&.application_type
        when "Integration"
          hash[:credential_type] = "GitHub app token"
        when "OauthApplication"
          hash[:credential_type] = "OAuth app token" unless credential_auth&.credential.personal_access_token?
        end
      end
    elsif credential_auth.credential_type == "PublicKey"
      hash[:fingerprint] = credential_auth.fingerprint
      hash[:authorized_credential_title] = credential_auth&.credential&.title
    end

    hash
  end
end
