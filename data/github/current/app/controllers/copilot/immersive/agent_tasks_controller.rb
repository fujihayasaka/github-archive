# typed: true
# frozen_string_literal: true

class Copilot::Immersive::AgentTasksController < Copilot::ImmersiveController
  before_action :check_agent_tasks_enabled, only: [:show]

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show, :user_access_denied]
  )

  def user_access_denied # rubocop:disable GitHub/UseRestfulActions
    context_region_preset :copilot

    # Redirect to the Agents page in case the user was shown the access denied page, got access, and then reloads the page
    # Also if we are using the new empty state for agents instead of the access denied page
    return redirect_to copilot_agent_tasks_show_path if agent_tasks_enabled? || agents_empty_state_enabled?

    public_user = Copilot::Public::User.new(current_user)
    message = if !public_user.has_copilot_access? || !public_user.has_required_sku_for_copilot_coding_agent?
      "#{Copilot::COPILOT_SWE_AGENT} is available with the GitHub Copilot Pro, Copilot Pro+, Copilot Business and Copilot Enterprise plans."
    elsif !public_user.swe_agent_enabled?
      "#{Copilot::COPILOT_SWE_AGENT} is not available because the #{Copilot::COPILOT_SWE_AGENT} policy has been disabled by an administrator."
    end

    render_react_html(
      app_name: "agent-sessions", # Needed until we rename the client package as it's still called agent-sessions
      title: "Agents · GitHub Copilot",
      payload: {
        accessDeniedRoute: {
          message:
        },
      },
    )
  end

  private

  memoize def agent_tasks_enabled?
    Copilot::Public::User.new(current_user).swe_agent_enabled?
  end

  def check_agent_tasks_enabled
    return if agent_tasks_enabled? || agents_empty_state_enabled?

    redirect_to copilot_agent_tasks_access_denied_path
  end

  def app_payload
    user = T.must(current_user)
    id_to_pull_request_map, tasks = tasks(user: user)
    # Call the base class method to get the default payload
    super.merge({
      pullRequestsMap: id_to_pull_request_map,
      tasks: tasks,
      sessionsPollingInterval: CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0,
      logsPollingInterval: CopilotSessions::Public.copilot_logs_polling_interval_seconds.value * 1000.0,
      currentUser: {
        id: user.id,
        login: user.display_login,
        userEmail: user.email || "#{user.display_login}@users.noreply.github.com",
        isStaff: user.employee?
      },
    })
  end

  def agents_empty_state_enabled?
    current_user.feature_flag_enabled?("copilot_chat_agents_empty_state", default: false)
  end

  # Fetch agent sessions for the current user
  def tasks(user:)
    return [] unless agent_tasks_enabled?
    CopilotSessions::DeprecatedTask.for_user_by_pull_requests(user:, user_session: user_session, cap_filter: cap_filter)
  end
end
