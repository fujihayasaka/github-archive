# typed: true
# frozen_string_literal: true

# This controller effectively mimics Repos::Agents::TasksController, but
# using the necessary backing to fit in as an immersive controller.
class Copilot::Immersive::TaskController < Copilot::ImmersiveController
  before_action :check_intent_detection, only: [:show]
  before_action :load_from_task, only: [:show]

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
    only: [:show]
  )

  attr_reader :task, :pull

  def show
    respond_to do |format|
      format.html { super }
      format.json { render json: app_payload }
    end
  end

  private

  def app_payload
    user = T.must(current_user)
    task_id = params[:task_id]

    # Prefetch the sessions for the PR
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :task_controller_show,
      user_session:)

    sessions = @task.sessions

    branch_alive_channel = @pull ? GitHub::WebSocket::Channels.signed_branch(current_repository, @pull.display_head_ref_name) : nil

    task_payload = Repos::Agents::TaskPayload.new(
      pull,
      repo_data,
      user,
      current_user_can_push?,
      steering_enabled?, # This is kind of redundant since we are blocking the page on the CCA policy, but keeping for consistency with MC and a future with other agents
      use_token_based_billing?,
      sessions,
      route_id: "unusedTaskRoute", # This controller backs old-school immersive not using data routes
      branch_alive_channel: branch_alive_channel,
      task_id: task_id,
      task: @task,
      token: token,
      sso_org_ids: saml_for_user.protected_organization_ids.map(&:to_s),
      agent_quota_snapshot: agent_quota_snapshot_for_user(user),
      remote_control_policy_enabled: Copilot::Public::User.for(current_user).cli_remote_control_enabled?,
    ).payload

    # Build the app payload from immersive + the task bits we need
    payload = {
      **immersive_chat_payload,
      **task_payload,
    }
  end

  def repo_data
    Repos::ReactPayload.current_repository_payload(
      current_repository,
      current_user_can_push: current_user_can_push?,
    )
  end

  def check_intent_detection
    render_404 unless current_user&.feature_flag_enabled?(:copilot_intent_detection, default: false)
  end

  def load_from_task
    user = T.must(current_user)
    return render_404 unless agent_tasks_enabled?

    repository = current_repository
    owner = T.must(repository.owner)
    task_id = params[:task_id]

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :agents_controller_task,
      user_session:
    )

    begin
      capi = Copilot::User.copilot_api(
        user:,
        integration_id: CopilotAPI::COPILOT_SWE_AGENT,
        token:
      )
      task_response = T.unsafe(capi).get_task(
        owner_display_login: owner.display_login,
        repo: repository.name,
        task_id:
      )
      @task = CopilotSessions::TaskApi::Task.new(
        task_response.is_a?(ConcurrentFaraday::FutureResponse) ? task_response.value : task_response
      )

      pull_request_id = @task.pull_request_id

      # Pull request is optional - tasks may not have an associated PR yet
      return unless pull_request_id

      @pull = PullRequest.find_by(id: pull_request_id)

      return unless @pull

      if @pull.hide_from_user?(current_user)
        render_404
        nil
      end
    rescue CopilotAPI::Error, GH::Errors::ObjectNotFound => e
      render_404
    end
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
