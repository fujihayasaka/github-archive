# typed: true
# frozen_string_literal: true

module Orgs::IdentityManagement
  class SingleSignOnView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :form_data, :organization, :initiate_sso_url, :credential_authorization_request

    def show_recovery_prompt?
      organization.adminable_by?(current_user)
    end

    def credential_authorization_requested?
      credential_authorization_request.present?
    end

    def valid_credential_authorization_request?
      credential_authorization_requested? && credential_authorization_request.valid?
    end

    def credential_type
      credential.is_a?(OauthAccess) ? "personal access token" : "SSH key"
    end

    def credential_description
      credential.is_a?(OauthAccess) ? credential.description : credential.title
    end

    def credential_link
      urls.settings_user_token_path(id: credential.id)
    end

    def invalid_credential_authorization_request_reason
      case credential_authorization_request.reason
      when :expired
        "expired"
      else
        "invalid"
      end
    end

    def credential
      @credential_type = credential_authorization_request.data["credential_type"]
      @credential = @credential_type.constantize.find_by_id(credential_authorization_request.data["credential_id"])
    end
  end
end
