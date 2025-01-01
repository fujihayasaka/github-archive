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
    return unless GitHub.flipper[:credential_revocation_api_mailers].enabled?
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
end
