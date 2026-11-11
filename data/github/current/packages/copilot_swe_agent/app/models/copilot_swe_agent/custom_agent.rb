# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class CustomAgent
    include GitHub::Memoizer

    sig { returns(T::Hash[String, T.untyped]) }
    attr_reader :custom_agent

    sig { params(custom_agent: T::Hash[String, T.untyped]).void }
    def initialize(custom_agent)
      @custom_agent = T.let(custom_agent.with_indifferent_access, T::Hash[String, T.untyped])
    end

    sig { returns(String) }
    def name
      custom_agent["name"]
    end

    sig { returns(T.nilable(String)) }
    def description
      custom_agent["description"]
    end

    sig { returns(String) }
    def display_name
      custom_agent["display_name"] || ""
    end

    sig do
      params(
        user: User,
        repo_owner: String,
        repo_name: String,
        token: T.nilable(Copilot::DecryptedToken),
        user_session: T.nilable(UserSession),
        use_staging: T::Boolean,
        use_staging_jedi_knight: T::Boolean,
        use_staging_sith_lord: T::Boolean,
      ).returns(T::Array[CustomAgent])
    end
    def self.for_repository(user:, repo_owner:, repo_name:, token: nil, user_session: nil, use_staging: false, use_staging_jedi_knight: false, use_staging_sith_lord: false)
      path = "#{SweAgentPath.base_path(use_staging:, use_staging_jedi_knight:, use_staging_sith_lord:)}/custom-agents/#{repo_owner}/#{repo_name}"
      response = CopilotAPI.make_request(
        token: token,
        integration_id: CopilotAPI::COPILOT_SWE_AGENT,
        user_id: user.id,
        real_ip: nil,
        method: :get,
        path: path
      )

      custom_agents = if response.is_a?(ConcurrentFaraday::FutureResponse)
        response.value.fetch("agents", [])
      else
        response.fetch("agents", [])
      end

      from_raw_custom_agents(custom_agents)
    end

    sig { params(custom_agents: T.nilable(T::Array[T::Hash[String, T.untyped]])).returns(T::Array[CustomAgent]) }
    def self.from_raw_custom_agents(custom_agents)
      return [] unless custom_agents
      custom_agents.map do |ca|
        new(ca.with_indifferent_access)
      end
    end
  end
end
