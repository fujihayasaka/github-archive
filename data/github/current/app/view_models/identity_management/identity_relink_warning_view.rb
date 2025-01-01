# typed: true
# frozen_string_literal: true

module IdentityManagement
  class IdentityRelinkWarningView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :saml_response, :relay_state, :identity_relink_session_token, :request_id, :target, :identity_relink_error, :form_submit_url, :sso_url

    def target_type
      target.is_a?(Business) ? "enterprise" : "organization"
    end

    def form_data
      {
        SAMLResponse: saml_response,
        RelayState: relay_state,
        IdentityRelinkSessionToken: identity_relink_session_token,
        RequestID: request_id,
      }
    end
  end
end
