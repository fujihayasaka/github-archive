# typed: true
# frozen_string_literal: true

# Controller for viewing tasks without requiring a repository context.
# Fetches the task by ID via the user-scoped CAPI endpoint (GET /agents/tasks/:task_id).
class Copilot::Immersive::UnscopedTaskController < Copilot::ImmersiveController
  before_action :load_task, only: [:show]

  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:show]
  )

  attr_reader :task

  def show
    respond_to do |format|
      format.html { super }
      format.json { render json: app_payload }
    end
  end

  private

  def app_payload
    user = T.must(current_user)

    sessions = @task.sessions

    task_payload = Repos::Agents::TaskPayload.new(
      nil, # pull
      nil, # repository
      user,
      false, # current_user_can_push
      steering_enabled?,
      use_token_based_billing?,
      sessions,
      route_id: "unusedTaskRoute",
      branch_alive_channel: nil,
      task_id: @task.id,
      task: @task,
      token: copilot_api_token,
      sso_org_ids: saml_for_user.protected_organization_ids.map(&:to_s),
      agent_quota_snapshot: agent_quota_snapshot_for_user(user),
      remote_control_policy_enabled: Copilot::Public::User.for(current_user).cli_remote_control_enabled?,
    ).payload

    {
      **immersive_chat_payload,
      **task_payload,
      sessionsPollingInterval: CopilotSessions::Public.copilot_sessions_polling_interval_seconds.value * 1000.0,
      logsPollingInterval: CopilotSessions::Public.copilot_logs_polling_interval_seconds.value * 1000.0,
    }
  end

  def load_task
    user = T.must(current_user)
    return render_404 unless agent_tasks_enabled?

    task_id = params[:task_id]

    begin
      capi = Copilot::User.copilot_api(
        user:,
        integration_id: CopilotAPI::COPILOT_SWE_AGENT,
        token: copilot_api_token
      )
      task_response = T.unsafe(capi).get_user_task(id: task_id)
      @task = CopilotSessions::TaskApi::Task.new(
        task_response.is_a?(ConcurrentFaraday::FutureResponse) ? task_response.value : task_response
      )

      # If the task has a repository, redirect to the repo-scoped task page
      repo_id = @task.repo_id
      if repo_id.present? && repo_id > 0
        repository = Repository.find_by(id: repo_id)
        if repository
          owner = T.must(repository.owner)
          redirect_to repo_task_path(user_id: owner.display_login, repository: repository.name, task_id: task_id)
        end
      end
    rescue CopilotAPI::Error, GH::Errors::ObjectNotFound, CopilotSessions::CopilotApiToken::IntegrationUnavailableError => e
      GitHub.logger.error("Failed to load unscoped task", {
        "code.function": "load_task",
        "code.namespace": self.class.name,
        "error.message": e.message,
        "error.class": e.class.name,
        "gh.copilot.task_id": params[:task_id],
      })
      render_404
    end
  end

  memoize def copilot_api_token
    CopilotSessions::CopilotApiToken.get_encrypted(
      user: T.must(current_user),
      entry_point: :unscoped_task_controller_show,
      user_session:
    )
  end

  memoize def agent_tasks_enabled?
    Copilot::Public::User.for(current_user).swe_agent_enabled?
  end

  memoize def steering_enabled?
    Copilot::Public::User.for(current_user).has_copilot_access?
  end

  # Fetches the current user's quota snapshot from the limiter client.
  sig { params(user: User).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def agent_quota_snapshot_for_user(user)
    Copilot::Users::AgentQuotaSnapshot.new.build(user: user)
  end

  memoize def use_token_based_billing?
    Copilot::Public::User.for(current_user).use_token_based_billing?
  end
end
