# typed: true
# frozen_string_literal: true

require "react_payload"

# Shared payload for the task view, used by TasksController, PullTasksController,
# and the immersive task controllers.
class Repos::Agents::TaskPayload < ReactPayload::Base
  sig do
    params(
      pull: T.nilable(PullRequest),
      repository: T.untyped,
      current_user: User,
      current_user_can_push: T::Boolean,
      steering_enabled: T::Boolean,
      use_token_based_billing: T::Boolean,
      sessions: T.untyped,
      route_id: String,
      branch_alive_channel: T.untyped,
      task_id: T.nilable(String),
      task: T.untyped,
      token: T.nilable(Copilot::EncryptedToken),
      sso_org_ids: T::Array[String],
      user_has_code_review_access: T::Boolean,
      agent_quota_snapshot: T.nilable(T::Hash[Symbol, T.untyped]),
      remote_control_policy_enabled: T::Boolean,
      automations_visible_for_current_user: T::Boolean,
    ).void
  end
  def initialize(pull, repository, current_user, current_user_can_push, steering_enabled, use_token_based_billing, sessions, route_id:, branch_alive_channel:, task_id:, task:, token: nil, sso_org_ids: [], user_has_code_review_access: false, agent_quota_snapshot: nil, remote_control_policy_enabled: false, automations_visible_for_current_user: false)
    @pull = pull
    @repository = repository
    @current_user = current_user
    @current_user_can_push = current_user_can_push
    @steering_enabled = steering_enabled
    @use_token_based_billing = use_token_based_billing
    @sessions = sessions
    @route_id = route_id
    @branch_alive_channel = branch_alive_channel
    @task_id = task_id
    @task = task
    @token = token
    @sso_org_ids = sso_org_ids
    @user_has_code_review_access = user_has_code_review_access
    @agent_quota_snapshot = agent_quota_snapshot
    @remote_control_policy_enabled = remote_control_policy_enabled
    @automations_visible = automations_visible_for_current_user
  end

  def route_id
    @route_id
  end

  def payload
    result = {
      pull: @pull ? CopilotSessions::Payloads::Pull.new(pull_request: @pull, include_body: false, include_diff: false).call : nil,
      repository: @repository,
      currentUser: CopilotSessions::Payloads::PublicUser.new(@current_user).call,
      currentUserCanPush: @current_user_can_push,
      steeringEnabled: @steering_enabled,
      remoteControlPolicyEnabled: @remote_control_policy_enabled,
      useTokenBasedBilling: @use_token_based_billing,
      agentQuotaSnapshot: @agent_quota_snapshot,
      sessionOwners: CopilotSessions::AgentSession.get_session_owners(@sessions),
      agentMentions: @pull ? CopilotSessions::Helpers.get_agent_mentions_for_sessions(@sessions, @pull) : [],
      sessions: @sessions.map(&:session),
      branchAliveChannel: @branch_alive_channel,
      taskId: @task_id,
      task: @task&.to_h,
      userHasCodeReviewAccess: @user_has_code_review_access,
      automationsVisible: @automations_visible,
    }

    if @token
      result[:initialAuthToken] = {
        token: @token.value,
        expiration: @token.expiration&.iso8601,
        ssoOrgIDs: @sso_org_ids
      }
    end

    result
  end
end
