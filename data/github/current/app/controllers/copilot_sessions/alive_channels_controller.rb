# typed: true
# frozen_string_literal: true

# Returns alive channels for a copilot agent sessions (creates, updates, log updates)
class CopilotSessions::AliveChannelsController < ApplicationController
  before_action :reject_enterprise
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  def show
    render json: {
      creates_channel: GitHub::WebSocket::Channels.signed_copilot_agent_session_create(current_user),
      updates_channel: GitHub::WebSocket::Channels.signed_copilot_agent_session_update(current_user),
      log_updates_channel: GitHub::WebSocket::Channels.signed_copilot_agent_session_log_update(current_user)
    }
  end

  private

  def reject_enterprise
    render_404 if GitHub.enterprise?
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
