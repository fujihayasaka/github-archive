# typed: true
# frozen_string_literal: true

class Copilot::Chat::TokensController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:create]

  before_action :not_administrative_blocked

  def create
    encrypted_token = helpers.copilot_mint_token(user_session, entry_point: :copilot_chat_tokens_controller_create)
    render json: {
      token: encrypted_token.value,
      expiration: encrypted_token.expiration,
      ssoOrgIDs: saml_for_user.protected_organization_ids.map(&:to_s)
    }
  rescue CopilotAPI::NetworkError => e
    report_error(e)
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def not_administrative_blocked
    render_404 if FeatureFlag.vexi.enabled?(:copilot_token_administrative_block, current_user, default: false) && Copilot::AdministrativeBlock.active.where(blockable: current_user).first
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
