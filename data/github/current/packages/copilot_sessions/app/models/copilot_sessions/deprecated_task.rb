# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # This is considered deprecated: it served as the initial modeling representing a task which
  # is a resource (likely a PR) with its associated agent sessions. It is considered deprecated
  # because it was based on CAPI's session endpoint and then layered on its own in-memory logic
  # here to do things like grouping and sorting. Instead, the go-forward will be to delegate those
  # responsibilities to CAPI and have the new Task model be a more 1:1 representation to CAPI's
  # endpoint. All usages should be migrated to use the new Task model once the new Task model
  # is in parity with this one or matches the desired future-state.
  class DeprecatedTask
    sig { returns(String) }
    attr_reader :resource_type

    sig { returns(Integer) }
    attr_reader :resource_id

    sig { returns(String) }
    attr_reader :resource_global_id

    sig { returns(Integer) }
    attr_reader :session_count

    sig { returns(String) }
    attr_reader :latest_session_updated_at

    sig { returns(String) }
    attr_reader :latest_session_state

    sig { returns(T::Boolean) }
    attr_reader :current_user_can_push

    sig do
      params(pull_id: Integer, sessions_for_pr: T::Array[AgentSession], current_user_can_push: T::Boolean).returns(T.nilable(DeprecatedTask))
    end
    def self.from_sessions(pull_id:, sessions_for_pr:, current_user_can_push: false)
      last_session = sessions_for_pr.max_by(&:last_updated_at)
      return nil unless last_session
      new(
        pull_id: pull_id,
        resource_global_id: last_session.resource_global_id,
        session_count: sessions_for_pr.count,
        latest_session_updated_at: last_session.last_updated_at,
        latest_session_state: last_session.state,
        current_user_can_push: current_user_can_push
      )
    end

    sig do
      params(user: User, cap_filter: T.nilable(ConditionalAccess::Web::Filter), user_session: T.nilable(UserSession)).returns([T::Hash[Integer, CopilotSessions::Payloads::Pull::PullHash], T::Array[DeprecatedTask]])
    end
    def self.for_user_by_pull_requests(user:, cap_filter: nil, user_session: nil)
      session_list = AgentSessionList.for_user(
        user:,
        entry_point: :agent_session_for_user_by_pull_requests,
        user_session:
      )

      sessions = session_list.agent_sessions

      return [{}, []] unless sessions.any?

      # Fetch pull requests with associations to prevent N+1 queries
      prs_ids = sessions.map(&:resource_id).uniq
      prs = PullRequest.includes(:repository).where(id: prs_ids).index_by(&:id)

      # Group sessions by pull request using Rails grouping
      sessions_by_pr_id = sessions.group_by(&:resource_id)

      tasks = sessions_by_pr_id.map do |pr_id, sessions_for_pr|
        # Get the pull request and check push access
        pr = prs[pr_id.to_i]
        can_push = if FeatureFlag.vexi.enabled?("copilot_swe_agent_task_push_access", user, default: false)
          pr&.repository&.authorized_to_write?(user) || false
        else
          false
        end

        # Create task with push access info
        DeprecatedTask.from_sessions(pull_id: pr_id.to_i, sessions_for_pr: sessions_for_pr, current_user_can_push: can_push)
      end
      tasks = tasks.compact
      tasks.sort_by! { |task| task.latest_session_updated_at }.reverse!

      id_to_pull_request_map = CopilotSessions::Public.id_to_pull_request_map(pull_request_ids: prs_ids.map(&:to_i), user: user, cap_filter: cap_filter)
      [id_to_pull_request_map, tasks]
    end

    sig do
      params(
        pull_id: Integer,
        resource_global_id: String,
        session_count: Integer,
        latest_session_updated_at: String,
        latest_session_state: String,
        current_user_can_push: T::Boolean
      ).void
    end
    def initialize(pull_id:, resource_global_id:, session_count:, latest_session_updated_at:, latest_session_state:, current_user_can_push: false)
      @resource_type = T.let("pull", String)
      @resource_id = T.let(pull_id, Integer)
      @resource_global_id = T.let(resource_global_id, String)
      @session_count = T.let(session_count, Integer)
      @latest_session_updated_at = T.let(latest_session_updated_at, String)
      @latest_session_state = T.let(latest_session_state, String)
      @current_user_can_push = T.let(current_user_can_push, T::Boolean)
    end
  end
end
