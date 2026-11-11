# typed: strict
# frozen_string_literal: true

module CopilotSessions
  module TaskApi
    # Represents a task from the CAPI Task API.
    class Task
      extend CapiResource

      CLI_SLUG = "copilot-developer-cli"
      VS_CODE_SLUG = "vscode-chat"

      sig do
        params(
          user: User,
          token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
          id: String,
          entry_point: Symbol,
        ).returns(T.nilable(Task))
      end
      def self.fetch_by_id(
        user:,
        token:,
        id:,
        entry_point: :agent_task_for_user
      )
        capi = capi_client(user:, entry_point:, token:)

        begin
          response = capi.get_user_task(id:)
        rescue CopilotAPI::NotFoundError
          return nil
        end

        hash = response.is_a?(ConcurrentFaraday::FutureResponse) ? response.value : response

        # Make sure a populated hash was returned or else treat it like a not found.
        return nil unless hash.present?

        new(hash)
      end

      sig do
        params(
          repository: Repository,
          user: User,
          token: T.nilable(T.any(Copilot::EncryptedToken, Copilot::DecryptedToken)),
          agent_id: T.nilable(Integer),
          base_ref: T.nilable(String),
          create_pull_request: T.nilable(T::Boolean),
          custom_agent: T.nilable(String),
          entry_point: Symbol,
          event_content: T.nilable(String),
          event_type: T.nilable(String),
          head_ref: T.nilable(String),
          model: T.nilable(String),
          problem_statement: T.nilable(String),
        ).returns(Task)
      end
      def self.create(
        repository:,
        user:,
        token:,
        agent_id: nil,
        base_ref: nil,
        create_pull_request: nil,
        custom_agent: nil,
        entry_point: :create_agent_task,
        event_content: nil,
        event_type: nil,
        head_ref: nil,
        model: nil,
        problem_statement: nil
      )
        capi = capi_client(user:, entry_point:, token:)

        response = capi.create_task(
          nwo: repository.name_with_display_owner,
          agent_id:,
          base_ref:,
          create_pull_request:,
          custom_agent:,
          event_content:,
          event_type:,
          head_ref:,
          model:,
          problem_statement:,
        )

        hash = sync_capi_response(response)

        # Handle both wrapped { "task": {...} } (legacy) and unwrapped root-level response
        # when copilot_task_api_github_rest_style is enabled.
        task_data = hash["task"] || hash
        new(task_data)
      end

      sig { params(data: T::Hash[String, T.untyped]).void }
      def initialize(data)
        @data = data
      end

      sig { returns(String) }
      def id
        @data["id"].to_s
      end

      sig { returns(Integer) }
      def creator_id
        @data.dig("creator", "id").to_i
      end

      sig { returns(String) }
      def status
        (@data["state"] || @data["status"]).to_s
      end

      sig { returns(Integer) }
      def session_count
        @data["session_count"].to_i
      end

      sig { returns(String) }
      def last_updated_at
        (@data["updated_at"] || @data["last_updated_at"]).to_s
      end

      sig { returns(String) }
      def created_at
        @data["created_at"].to_s
      end

      sig { returns(T.nilable(String)) }
      def archived_at
        @data["archived_at"]&.to_s
      end

      sig { returns(T.nilable(Integer)) }
      def repo_id
        @data.dig("repository", "id")&.to_i
      end

      sig { returns(T.any(Promise[NilClass], Promise[T.nilable(Repository)])) }
      def async_repository
        return Promise.resolve(nil) if repo_id.blank?

        Platform::Loaders::ActiveRecord.load(::Repository, repo_id, security_violation_behaviour: :nil)
      end

      # Returns the task name for display as a title in a project table row.
      # The name is a human-readable summary derived from the task prompt
      # by the mission control service.
      sig { returns(T.nilable(String)) }
      def title
        @data["name"]&.to_s
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def artifacts
        @data["artifacts"] || []
      end

      # Returns the pull request ID from the first GitHub artifact with type "pull".
      # Returns nil if no matching artifact is found.
      sig { returns(T.nilable(Integer)) }
      def pull_request_id
        artifact = github_pull_artifact
        return nil unless artifact

        artifact.dig("data", "id")&.to_i
      end

      # Returns the pull request global ID from the first GitHub artifact with type "pull".
      # Returns nil if no matching artifact is found.
      sig { returns(T.nilable(String)) }
      def pull_request_global_id
        artifact = github_pull_artifact
        return nil unless artifact

        artifact.dig("data", "global_id")&.to_s
      end

      # Returns true if this task has a pull request artifact.
      sig { returns(T::Boolean) }
      def pull_request?
        !github_pull_artifact.nil?
      end

      # Returns true if this task is being handled by a CLI (remote) agent.
      # A task is considered to have a CLI agent if any agent_collaborator
      # has a slug matching the CLI agent slug.
      sig { returns(T::Boolean) }
      def cli_agent?
        agent_collaborators = @data["agent_collaborators"]
        return false if agent_collaborators.nil? || agent_collaborators.empty?

        agent_collaborators.any? do |collaborator|
          collaborator["slug"].to_s == CLI_SLUG
        end
      end

      # Returns the type of agent that created this task based on the agent_collaborators.
      # Checks agent collaborator slugs to determine the agent type.
      sig { returns(AgentType) }
      def agent_type
        agent_collaborators = @data["agent_collaborators"]

        (agent_collaborators || []).each do |collaborator|
          slug = collaborator["slug"].to_s
          if slug == CLI_SLUG
            return AgentType::CLI
          elsif slug == VS_CODE_SLUG
            return AgentType::VSCode
          end
        end

        AgentType::Cloud
      end

      # Returns the serialized agent type as a string for use in GraphQL.
      sig { returns(String) }
      def serialized_agent_type
        agent_type.serialize
      end

      # Returns the sessions associated with this task.
      sig { returns(T::Array[AgentSession]) }
      def sessions
        sessions_data = @data["sessions"] || []
        sessions_data.map { |session_data| AgentSession.new(session_data) }
      end

      # Returns the raw hash representation for serialization to the frontend.
      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        @data
      end

      private

      # Finds the first GitHub artifact with type "pull".
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def github_pull_artifact
        artifacts.find do |artifact|
          artifact["provider"] == "github" && artifact.dig("data", "type") == "pull"
        end
      end
    end
  end
end
