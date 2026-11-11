# typed: strict
# frozen_string_literal: true

module CopilotSessions
  # The parent class represents the bare minimum information required for a session to exist across
  # parent and child associations. This subclass extends that and rounds out the full session object
  # as represented by the CAPI response.
  class AgentSession < PartialAgentSession
    extend CapiResource

    sig  { params(user: User, pull: PullRequest, token: T.nilable(Copilot::EncryptedToken), user_session: T.nilable(UserSession)).returns(T::Array[AgentSession]) }
    def self.for_pull_request(user:, pull:, token: nil, user_session: nil)
      response = capi_client(user:, entry_point: :agent_session_for_pull_requests, token:, user_session:).get_swe_agent_sessions(resource_type: "pull", resource_id: pull.id)
      hash = sync_capi_response(response)
      sessions = hash["sessions"] || []

      from_raw_sessions(sessions)
    end

    sig { params(user: User, session_id: String, token: T.nilable(T.any(Copilot::DecryptedToken, Copilot::EncryptedToken)), entry_point: Symbol, user_session: T.nilable(UserSession)).returns(T.nilable(AgentSession)) }
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

    sig { params(sessions: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[AgentSession]) }
    def self.from_raw_sessions(sessions)
      return [] unless sessions
      sessions.map do |session_data|
        new(session_data.with_indifferent_access)
      end
    end
    sig { params(sessions: T::Array[AgentSession]).returns(T::Array[CopilotSessions::Payloads::PublicUser::UserHash]) }
    def self.get_session_owners(sessions)
      user_ids = sessions.map { |s| s.user_id }.compact.uniq
      users = User.where(id: user_ids)
      users.map do |user|
        CopilotSessions::Payloads::PublicUser.new(user).call
      end
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
    def resource_global_id
      session["resource_global_id"]
    end

    sig { returns(String) }
    def completed_at
      session["completed_at"]
    end

    sig { returns(Integer) }
    def user_id
      session["user_id"]
    end

    sig { returns(String) }
    def event_type
      session["event_type"]
    end

    sig { returns(T::Array[String]) }
    def event_identifiers
      session["event_identifiers"]
    end

    sig { returns(T.nilable(String)) }
    def event_content
      session["event_content"]
    end

    sig { returns(T.any(Promise[T.nilable(PullRequest)], Promise[NilClass])) }
    def async_resource
      # Ensure the resource is a pull request and that we have an ID to load.
      return Promise.resolve(nil) unless pr_resource?

      # Using a loader here should avoid N+1 queries while fetching resources across AgentSession instances.
      Platform::Loaders::ActiveRecord.load(::PullRequest, session["resource_id"])
    end

    private

    sig { returns(T::Boolean) }
    def pr_resource?
      session["resource_type"] == "pull" && resource_id.present?
    end
  end
end
