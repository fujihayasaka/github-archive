# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class Task

    sig { returns(String) }
    attr_reader :resource_type

    sig { returns(Integer) }
    attr_reader :resource_id

    sig { returns(Integer) }
    attr_reader :session_count

    sig { returns(String) }
    attr_reader :latest_session_updated_at

    sig { returns(String) }
    attr_reader :latest_session_state

    sig do
      params(pull_id: Integer, sessions_for_pr: T::Array[AgentSession]).returns(T.nilable(Task))
    end
    def self.from_sessions(pull_id:, sessions_for_pr:)
      last_session = sessions_for_pr.max_by(&:last_updated_at)
      return nil unless last_session
      new(
        pull_id: pull_id,
        session_count: sessions_for_pr.count,
        latest_session_updated_at: last_session.last_updated_at,
        latest_session_state: last_session.state
      )
    end

    sig do
      params(user: User, user_session: T.nilable(UserSession)).returns([T::Hash[Integer, Payloads::Pull::PullHash], T::Array[Task]])
    end
    def self.for_user_by_pull_requests(user:, user_session: nil)
      sessions = AgentSession.for_user(user: user, entry_point: :agent_session_for_user_by_pull_requests, user_session: user_session)
      return [{}, []] unless sessions.any?

      # Fetch pull requests with associations to prevent N+1 queries
      prs_ids = sessions.map(&:resource_id).uniq
      prs = PullRequest.includes(:repository).where(id: prs_ids).index_by(&:id)

      # Group sessions by pull request using Rails grouping
      sessions_by_pr_id = sessions.group_by(&:resource_id)

      tasks = sessions_by_pr_id.map do |pr_id, sessions_for_pr|
        Task.from_sessions(pull_id: pr_id.to_i, sessions_for_pr: sessions_for_pr)
      end.compact
      tasks.sort_by! { |task| task.latest_session_updated_at }.reverse!

      id_to_pull_request_map = CopilotSweAgent::Public.id_to_pull_request_map(pull_request_ids: prs_ids.map(&:to_i), user: user)
      [id_to_pull_request_map, tasks]
    end

    sig do
      params(
        pull_id: Integer,
        session_count: Integer,
        latest_session_updated_at: String,
        latest_session_state: String
      ).void
    end
    def initialize(pull_id:, session_count:, latest_session_updated_at:, latest_session_state:)
      @resource_type = T.let("pull", String)
      @resource_id = T.let(pull_id, Integer)
      @session_count = T.let(session_count, Integer)
      @latest_session_updated_at = T.let(latest_session_updated_at, String)
      @latest_session_state = T.let(latest_session_state, String)
    end
  end
end
