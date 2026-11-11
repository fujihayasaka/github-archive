# typed: true
# frozen_string_literal: true

class RevokedCredentialMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/revoked_credential"

  layout "layouts/primer_layout"
  helper :avatar

  sig { params(user: User, key_name: String, type: T.nilable(Symbol)).void }
  def personal_access_token_revoked(user, key_name, type: nil)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_api_mailers, default: false)
    return unless [TokenRevocation::Helper::FG_PAT_CREDENTIAL, TokenRevocation::Helper::PAT_CREDENTIAL].include?(type)

    @user = user
    @key_name = key_name
    if type == TokenRevocation::Helper::FG_PAT_CREDENTIAL
      @pat_type = "fine-grained personal access token"
      @new_pat_url = settings_user_access_tokens_url
    else
      @pat_type = "personal access token"
      @new_pat_url = settings_user_tokens_url
    end
    @title = "Your #{@pat_type} has been revoked"
    subject = "[GitHub] Your #{@pat_type}, #{@key_name}, has been revoked"

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: subject,
    )
  end

  sig { params(user: User, app_name: String, scopes: T.nilable(T::Array[String])).void }
  def oauth_token_revoked(user, app_name, scopes: nil)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_api_mailers, default: false)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_oauth_app_mailers, default: false)

    @user = user
    @app_name = app_name
    @scopes = scopes
    @title = "Your OAuth app access has been revoked"
    @authorized_apps_url = settings_user_applications_url
    subject = "[GitHub] Your access to #{@app_name} has been revoked"

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: subject,
    )
  end

  sig { params(user: User, app_name: String).void }
  def github_app_user_to_server_token_revoked(user, app_name)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_api_mailers, default: false)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_u2s_mailers, default: false)

    @user = user
    @app_name = app_name
    @title = "Your GitHub App access has been revoked"
    @authorized_apps_url = settings_user_app_authorizations_url
    subject = "[GitHub] Your access to #{@app_name} has been revoked"

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: subject,
    )
  end

  sig { params(user: User, app_name: String).void }
  def github_app_refresh_token_revoked(user, app_name)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_api_mailers, default: false)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_refresh_token_mailers, default: false)

    @user = user
    @app_name = app_name
    @title = "Your GitHub App access has been revoked"
    @authorized_apps_url = settings_user_app_authorizations_url
    subject = "[GitHub] Your access to #{@app_name} has been revoked"

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: subject,
    )
  end

  sig { params(user: User, app_name: String).void }
  def github_app_server_to_server_token_revoked(user, app_name)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_api_mailers, default: false)
    return unless FeatureFlag.vexi.enabled?(:credential_revocation_s2s_mailers, default: false)

    @user = user
    @app_name = app_name
    @title = "A GitHub App installation token has been revoked"
    @developer_apps_url = settings_user_apps_url
    subject = "[GitHub] An installation token for #{@app_name} has been revoked"

    premail(
      from: github_noreply,
      to: user_email(@user),
      subject: subject,
    )
  end
end
