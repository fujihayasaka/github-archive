# typed: strict
# frozen_string_literal: true

module CopilotSessions
  class AgentSessionList
    extend CapiResource

    sig  do
      params(
        user: User,
        entry_point: Symbol,
        user_session: T.nilable(UserSession),
        token: T.nilable(Copilot::DecryptedToken),
        page_number: T.nilable(Integer),
        page_size: T.nilable(Integer),
        sort_field: T.nilable(SessionSortField),
        sort_direction: T.nilable(SortDirection),
        session_states: T.nilable(T::Array[SessionState]),
      ).returns(AgentSessionList)
    end
    def self.for_user(
      user:,
      entry_point: :agent_session_for_user,
      user_session: nil,
      token: nil,
      page_number: nil,
      page_size: nil,
      sort_field: nil,
      sort_direction: nil,
      session_states: nil
    )
      capi = capi_client(user:, entry_point: entry_point, user_session:, token:)

      response = capi.list_user_swe_agent_sessions(
        page_number:,
        page_size:,
        sort_field: sort_field ? sort_field.serialize : nil,
        sort_direction: sort_direction ? sort_direction.serialize : nil,
        session_states: session_states ? session_states.map(&:serialize) : nil
      )

      hash = sync_capi_response(response)

      from_raw(hash)
    end

    sig { params(hash: T::Hash[String, T.untyped]).returns(AgentSessionList) }
    def self.from_raw(hash)
      sessions = hash["sessions"] || []
      has_next_page = hash["has_next_page"] || false
      agent_sessions = AgentSession.from_raw_sessions(sessions)

      new(agent_sessions:, has_next_page:)
    end

    sig { returns(T::Array[AgentSession]) }
    attr_reader :agent_sessions

    sig { returns(T::Boolean) }
    attr_reader :has_next_page

    sig { params(agent_sessions: T::Array[AgentSession], has_next_page: T::Boolean).void }
    def initialize(agent_sessions:, has_next_page:)
      @agent_sessions = agent_sessions
      @has_next_page = has_next_page
    end
  end
end
