# typed: true
# frozen_string_literal: true

class Copilot::Immersive::AgentSessionsController < Copilot::ImmersiveController
  before_action :check_agent_sessions_enabled

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]
  )

  private

  def check_agent_sessions_enabled
    render_404 unless user_feature_enabled?(:copilot_immersive_agent_sessions)
  end

  def app_payload
    user = T.must(current_user)

    # Call the base class method to get the default payload
    super.merge({
      agentSessions: agent_sessions(user: user)
    })
  end

  # Fetch agent sessions for the current user
  def agent_sessions(user:)
    return [] unless user.feature_enabled?(:copilot_immersive_agent_sessions)
    CopilotSweAgent::AgentSession.for_user_by_pull_requests(user:, user_session: user_session)
  end
end
