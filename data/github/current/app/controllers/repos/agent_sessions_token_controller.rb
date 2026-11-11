# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsTokenController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create]
  before_action :login_required
  before_action :disallow_enterpise

  def create
    GitHub.logger.info(
      "agent_sessions_token_controller create called",
      {
        "gh.user.id" => current_user.id,
        "gh.copilot_coding_agent.has_user_session" => user_session.present?,
        "gh.copilot_coding_agent.force_refresh" => force_refresh?,
        "gh.request_id" => GitHub.context[:request_id],
      }
    )

    encrypted_token = CopilotSessions::CopilotApiToken.get_encrypted(
      user: current_user,
      entry_point: :agent_sessions_token_controller_create,
      user_session: user_session,
      force_cache_miss: force_refresh?
    )

    # Only return token, expiration, and SSO org IDs - refresh token stays server-side in session cache
    render json: {
      token: encrypted_token.value,
      expiration: encrypted_token.expiration,
      ssoOrgIDs: saml_for_user.protected_organization_ids.map(&:to_s)
    }
  end

  private

  def force_refresh?
    params[:force_refresh] == "true" || params[:force_refresh] == true
  end

  # CAP is not bypassed here as AgentSessionsBaseController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def disallow_enterpise
    render_404 if GitHub.enterprise? || (GitHub.multi_tenant_enterprise? && !FeatureFlag.vexi.enabled?(:coding_agent_in_proxima, GitHub::CurrentTenant.get, default: false))
  end
end
