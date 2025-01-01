# typed: true
# frozen_string_literal: true

class Copilot::Chat::TokensController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:create]

  def create
    encrypted_token = helpers.copilot_mint_token(user_session, entry_point: :copilot_chat_tokens_controller_create)
    render json: { token: encrypted_token.value, expiration: encrypted_token.expiration }
  rescue CopilotAPI::NetworkError => e
    report_error(e)
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
