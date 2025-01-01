# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class AgentSession
    include GitHub::Memoizer

    sig  { params(user: User, entry_point: Symbol, user_session: T.nilable(UserSession), token: T.nilable(Copilot::DecryptedToken)).returns(T::Array[AgentSession]) }
    def self.for_user(user:, entry_point: :agent_session_for_user, user_session: nil, token: nil)
      response = capi_client(user:, entry_point: entry_point, user_session:, token:).list_user_swe_agent_sessions
      sessions = if response.is_a?(ConcurrentFaraday::FutureResponse)
        response.value.fetch("sessions", [])
      else
        response.fetch("sessions", [])
      end

      from_raw_sessions(sessions)
    end

    sig  { params(user: User, pull: PullRequest, token: T.nilable(Copilot::EncryptedToken), user_session: T.nilable(UserSession)).returns(T::Array[AgentSession]) }
    def self.for_pull_request(user:, pull:, token: nil, user_session: nil)
      response = capi_client(user:, entry_point: :agent_session_for_pull_requests, token:, user_session:).get_swe_agent_sessions(resource_type: "pull", resource_id: pull.id)
      sessions = if response.is_a?(ConcurrentFaraday::FutureResponse)
        response.value.fetch("sessions", [])
      else
        response.fetch("sessions", [])
      end

      from_raw_sessions(sessions)
    end

    sig { params(user: User, session_id: String, token: T.nilable(Copilot::DecryptedToken), entry_point: Symbol, user_session: T.nilable(UserSession)).returns(T.nilable(AgentSession)) }
    def self.for_session(user:, session_id:, token:, entry_point: :agent_session_for_user_single, user_session: nil)
      begin
        response = capi_client(
          user:,
          entry_point: entry_point,
          user_session:,
          token:
        ).get_swe_agent_session(session_id: session_id)
      rescue CopilotAPI::NotFoundError => _e
        # We couldn't find the session, let caller raise NotFound if needed
        return nil
      end
      session = if response.is_a?(ConcurrentFaraday::FutureResponse)
        response.value
      else
        response
      end

      return nil unless session.present?
      new(session.with_indifferent_access)
    end

    sig do
      params(
        user: User,
        entry_point: Symbol,
        token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
        user_session: T.nilable(UserSession)
      ).returns(Copilot::User::CopilotApi)
    end
    def self.capi_client(user:, entry_point:, token: nil, user_session: nil)
      api_token = token || CopilotApiToken.get_encrypted(user: user, entry_point: :agent_session_for_pull_requests, user_session: user_session)
      user.copilot_api(integration_id: CopilotAPI::COPILOT_SWE_AGENT, token: api_token)
    end
    private_class_method :capi_client

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :session

    sig { params(session: T::Hash[String, T.untyped]).void }
    def initialize(session)
      @session = session
      @pull_request = T.let(nil, T.nilable(PullRequest))
    end

    sig { returns(String) }
    def id
      session["id"]
    end

    sig { returns(String) }
    def created_at
      session["created_at"]
    end

    sig { returns(String) }
    def name
      session["name"]
    end

    sig { returns(Integer) }
    def resource_id
      session["resource_id"]
    end

    sig { returns(String) }
    def last_updated_at
      session["last_updated_at"]
    end

    sig { returns(String) }
    def completed_at
      session["completed_at"]
    end

    sig { returns(String) }
    def state
      session["state"]
    end

    sig { returns(T.any(Promise[T.nilable(PullRequest)], Promise[NilClass])) }
    def async_resource
      # Ensure the resource is a pull request and that we have an ID to load.
      return Promise.resolve(nil) unless pr_resource?

      # Using a loader here should avoid N+1 queries while fetching resources across AgentSession instances.
      Platform::Loaders::ActiveRecord.load(::PullRequest, session["resource_id"])
    end

    sig { params(sessions: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[AgentSession]) }
    def self.from_raw_sessions(sessions)
      return [] unless sessions
      sessions.map do |session_data|
        new(session_data.with_indifferent_access)
      end
    end

    private

    sig { returns(T::Boolean) }
    def pr_resource?
      session["resource_type"] == "pull" && resource_id.present?
    end
  end
end
