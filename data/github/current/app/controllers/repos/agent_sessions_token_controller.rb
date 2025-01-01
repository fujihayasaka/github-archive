# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsTokenController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]
  before_action :login_required
  before_action :disallow_enterpise

  def create
    encrypted_token = CopilotSweAgent::CopilotApiToken.get_encrypted(user: current_user, entry_point: :agent_sessions_token_controller_create, user_session:, force_cache_miss: true)
    expiration = [Time.now + 1.hour, encrypted_token.expiration].min
    render json: { token: encrypted_token.value, expiration: }
  end

  private

  # CAP is not bypassed here as AgentSessionsBaseController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def disallow_enterpise
    render_404 if GitHub.enterprise? || (GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, GitHub::CurrentTenant.get, default: false))
  end
end
