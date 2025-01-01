# typed: true
# frozen_string_literal: true

module Orgs::IdentityManagement
  class CredentialAuthorizedView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :organization, :return_to, :credential_authorization

    def credential_type
      credential.is_a?(OauthAccess) ? "personal access token" : "SSH key"
    end

    def credential_description
      credential.is_a?(OauthAccess) ? credential.description : credential.title
    end

    def credential_link
      credential.is_a?(OauthAccess) ? urls.settings_user_token_path(id: credential.id) : urls.settings_key_path(credential.id)
    end

    def credential
      credential_authorization.credential
    end
  end
end
