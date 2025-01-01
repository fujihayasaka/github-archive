# typed: true
# frozen_string_literal: true

class Copilot::Immersive::AgentSessionsController < Copilot::ImmersiveController
  before_action :check_agent_sessions_enabled, only: [:show]
  before_action :check_task_view_enabled, only: [:show_task_view]

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
    only: [:show, :user_access_denied, :show_task_view]
  )

  def show_task_view # rubocop:disable GitHub/UseRestfulActions
    show
  end

  def user_access_denied # rubocop:disable GitHub/UseRestfulActions
    context_region_preset :copilot

    # Redirect to the Agents page in case the user was shown the access denied page, got access, and then reloads the page
    return redirect_to copilot_agents_show_path if agent_sessions_enabled?

    public_user = Copilot::Public::User.new(current_user)
    message = if !public_user.has_copilot_access? || !public_user.has_required_sku_for_copilot_coding_agent?
      "#{Copilot::COPILOT_SWE_AGENT} is available with the GitHub Copilot Pro, Copilot Pro+, Copilot Business and Copilot Enterprise plans."
    elsif !public_user.swe_agent_enabled?
      "#{Copilot::COPILOT_SWE_AGENT} is not available because the #{Copilot::COPILOT_SWE_AGENT} policy has been disabled by an administrator."
    end

    render_react_html(
      title: "Agents · GitHub Copilot",
      payload: {
        accessDeniedRoute: {
          message:
        },
      },
    )
  end

  private

  memoize def agent_sessions_enabled?
    Copilot::Public::User.new(current_user).swe_agent_enabled?
  end

  def check_task_view_enabled
    render_404 unless current_user&.feature_flag_enabled?(:copilot_mission_control, default: false)
  end

  def check_agent_sessions_enabled
    return if agent_sessions_enabled?

    redirect_to copilot_agents_access_denied_path
  end

  def app_payload
    user = T.must(current_user)
    id_to_pull_request_map, tasks = tasks(user: user)
    # Call the base class method to get the default payload
    super.merge({
      pullRequestsMap: id_to_pull_request_map,
      tasks: tasks,
      sessionsPollingInterval: CopilotSweAgent::Public.copilot_sessions_polling_interval_seconds.value * 1000.0,
      logsPollingInterval: CopilotSweAgent::Public.copilot_logs_polling_interval_seconds.value * 1000.0,
    })
  end

  # Fetch agent sessions for the current user
  def tasks(user:)
    return [] unless agent_sessions_enabled?
    CopilotSweAgent::Task.for_user_by_pull_requests(user:, user_session: user_session)
  end
end
