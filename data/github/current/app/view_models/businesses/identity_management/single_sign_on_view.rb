# typed: true
# frozen_string_literal: true

module Businesses::IdentityManagement
  class SingleSignOnView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :form_data, :business, :initiate_sso_url, :credential_authorization_request, :account_switcher_helper, :return_to

    def show_recovery_prompt?
      business.adminable_by?(current_user)
    end

    def show_first_emu_owner_login_prompt?
      # do not show login prompt if the current_user is already present or the business is adminable by the current_user
      return false if current_user.present? || business.adminable_by?(current_user)
      return true if business&.enterprise_managed_user_enabled?
      false
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
      return if credential_authorization_request.reason == :valid

      case credential_authorization_request.reason
      when :expired
        "expired"
      else
        "invalid"
      end
    end

    def credential
      return unless credential_authorization_request
      @credential_type ||= credential_authorization_request.data["credential_type"]
      @credential ||= @credential_type.constantize.find_by_id(credential_authorization_request.data["credential_id"])
    end

    def credential_authorization_organization
      return unless credential_authorization_request
      @organization ||= Organization.find_by(id: credential_authorization_request.data["organization_id"])
    end

    def accounts_eligible_to_switch?
      switchable_accounts_for_business&.any?
    end

    def accounts_eligible_to_switch
      switchable_accounts_for_business
    end

    private

    def switchable_accounts_for_business
      return [] unless logged_in?
      return [] unless account_switcher_helper && account_switcher_helper.enabled?
      return [] unless business.enterprise_managed_user_enabled?

      account_switcher_helper.stashed_accounts.valid.select do |account|
        account.user.enterprise_managed_business&.id == business.id &&
          !account.user.is_first_emu_owner? &&
          account.user_session.external_identity_sessions.active.any?
      end
    end
  end
end
