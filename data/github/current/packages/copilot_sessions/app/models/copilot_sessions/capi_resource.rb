# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # Some common methods used across objects that interact with the Copilot API.
  module CapiResource
    sig do
      params(
        response: T.any(
          ActiveSupport::HashWithIndifferentAccess,
          ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess],
          T::Hash[String, T.untyped]
        ),
      ).returns(ActiveSupport::HashWithIndifferentAccess)
    end
    def sync_capi_response(response)
      if response.is_a?(ConcurrentFaraday::FutureResponse)
        response.value
      else
        response.with_indifferent_access
      end
    end

    sig do
      params(
        user: User,
        entry_point: Symbol,
        token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
        user_session: T.nilable(UserSession)
      ).returns(Copilot::User::CopilotApi)
    end
    def capi_client(user:, entry_point:, token: nil, user_session: nil)
      api_token = token || CopilotApiToken.get_encrypted(
        user: user,
        entry_point: :agent_session_for_pull_requests,
        user_session: user_session
      )

      Copilot::User.copilot_api(user: user, integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: api_token)
    end
  end
end
