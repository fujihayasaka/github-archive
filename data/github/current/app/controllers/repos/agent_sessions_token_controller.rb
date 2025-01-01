# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsTokenController < Repos::AgentSessionsBaseController
  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]

  def create
    encrypted_token = copilot_api_token(entry_point: :agent_sessions_token_controller_create)
    render json: { token: encrypted_token.value, expiration: encrypted_token.expiration }
  end

  private

  # CAP is not bypassed here as AgentSessionsBaseController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  sig { params(entry_point: Symbol).returns(Copilot::EncryptedToken) }
  def copilot_api_token(entry_point:)
    token, expires_at = CopilotSweAgent::AgentSession.mint_token(user: current_user, entry_point:, extended_expiry: true, user_session: user_session)
    encrypted = simple_box.encrypt(token.to_s)
    encoded = Base64.urlsafe_encode64(encrypted)

    Copilot::EncryptedToken.from(encoded, expiration: expires_at)
  end

  sig { returns(RbNaCl::SimpleBox) }
  memoize def simple_box
    T.must_because(GitHub.dotcom_capi_simple_box) { "must have an encryption key set" }
  end
end
