# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class AgentSession
    include GitHub::Memoizer

    sig  { params(user: User, entry_point: T.nilable(Symbol), user_session: T.nilable(UserSession)).returns(T::Array[AgentSession]) }
    def self.for_user(user:, entry_point: :agent_session_for_user, user_session: nil)
      sessions = if GitHub.copilot_swe_agent_mock_session_data
        mock_session_data
      else
        response = capi_client(user:, entry_point: T.must(entry_point), user_session:).list_user_swe_agent_sessions
        if response.is_a?(ConcurrentFaraday::FutureResponse)
          response.value.fetch("sessions", [])
        else
          response.fetch("sessions", [])
        end
      end

      from_raw_sessions(sessions)
    end

    sig do
      params(user: User, user_session: T.nilable(UserSession)).returns(T::Array[{
        pull: Payloads::Pull::PullHash,
        sessions: T::Array[AgentSession]
      }])
    end
    def self.for_user_by_pull_requests(user:, user_session: nil)
      sessions = for_user(user: user, entry_point: :agent_session_for_user_by_pull_requests, user_session: user_session)
      return [] unless sessions.any?

      # Fetch pull requests with associations to prevent N+1 queries
      prs_ids = sessions.map(&:resource_id).uniq
      prs = PullRequest.includes(:repository).order(:updated_at).where(id: prs_ids).index_by(&:id)

      # Group sessions by pull request using Rails grouping
      sessions_by_pr_id = sessions.group_by(&:resource_id)

      prs.filter_map do |pr_id, pr|
        sessions_for_pr = sessions_by_pr_id[pr_id]
        next unless sessions_for_pr&.any?

        {
          pull: Payloads::Pull.new(pull_request: pr).call,
          sessions: sessions_for_pr,
        }
      end
    end

    sig  { params(user: User, pull: PullRequest, token: T.nilable(Copilot::DecryptedToken), user_session: T.nilable(UserSession)).returns(T::Array[AgentSession]) }
    def self.for_pull_request(user:, pull:, token: nil, user_session: nil)
      sessions = if GitHub.copilot_swe_agent_mock_session_data
        mock_session_data
      else
        response = capi_client(user:, entry_point: :agent_session_for_pull_requests, token:, user_session:).get_swe_agent_sessions(resource_type: "pull", resource_id: pull.id)
        if response.is_a?(ConcurrentFaraday::FutureResponse)
          response.value.fetch("sessions", [])
        else
          response.fetch("sessions", [])
        end
      end

      from_raw_sessions(sessions)
    end

    sig { params(user: User, entry_point: Symbol, extended_expiry: T::Boolean, user_session: T.nilable(UserSession)).returns([Copilot::DecryptedToken, Time]) }
    def self.mint_token(user:, entry_point:, extended_expiry: false, user_session: nil)
      # TODO: Cache this token so we don't create a new one every time
      GitHub.tracer.in_span("copilot_agent_session#mint_token", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.mint_token.latency") do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          new_access = app.grant(user, { user_session: user_session, entry_point: entry_point })
          token, _ = new_access.redeem(extended_expiry:)
          GitHub.logger.info(
            "copilot_agent_session token minted",
            {
              "gh.user.id" => user.id,
              "gh.catalog_service" => "github/copilot-coding-agent",
              "gh.copilot_coding_agent.mint_token.entry_point" => entry_point,
              "gh.copilot_coding_agent.mint_token.extended_expiry" => extended_expiry,
              "gh.request_id" => GitHub.context[:request_id],
            }
          )
          [Copilot::DecryptedToken.from(token), new_access.expires_at]
        end
      end
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.mock_session_data
      s = JSON.parse(File.read("ui/packages/agent-sessions/mocks/sessions_response.json"))&.dig("sessions")
      pr = PullRequest.first
      s.map do |session|
        session["resource_id"] = pr&.id
        session["repo_id"] = pr&.repository&.id
        session
      end
    end

    sig  { params(user: User, entry_point: Symbol, token: T.nilable(Copilot::DecryptedToken), user_session: T.nilable(UserSession)).returns(Copilot::User::CopilotApi) }
    def self.capi_client(user:, entry_point:, token: nil, user_session: nil)
      api_token = token || mint_token(user: user, entry_point: :agent_session_for_pull_requests, user_session: user_session).first
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

    sig { returns(Integer) }
    def resource_id
      session["resource_id"]
    end

    sig { params(sessions: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[AgentSession]) }
    def self.from_raw_sessions(sessions)
      return [] unless sessions
      sessions.map do |session_data|
        new(session_data.with_indifferent_access)
      end
    end

  end
end
