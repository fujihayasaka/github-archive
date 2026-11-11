# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Viewer
      module Agentic
        include Interfaces::Base
        include Helpers::Agentic

        docs_category :copilot
        description "Copilot Agentic fields in context of the current viewer."

        field :viewer_copilot_agent_creates_channel,
          String, "Channel value for subscribing to live updates for session creations.",
          null: true

        def viewer_copilot_agent_creates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_create(@object)
        end

        field :viewer_copilot_agent_updates_channel,
          String, "Channel value for subscribing to live updates for session updates.",
          null: true

        def viewer_copilot_agent_updates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_update(@object)
        end

        field :viewer_copilot_agent_log_updates_channel,
          String, "Channel value for subscribing to live updates for session log updates.",
          null: true

        def viewer_copilot_agent_log_updates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_log_update(@object)
        end

        field :viewer_copilot_agent_task_updates_channel,
          String, "Channel value for subscribing to live updates for task updates.",
          null: true

        def viewer_copilot_agent_task_updates_channel
          return unless is_viewer

          GitHub::WebSocket::Channels.signed_copilot_agent_session_task_update(@object)
        end

        field :viewer_copilot_agent_repository_suggestions,
          [Objects::Repository],
          null: false,
          description: <<~DESCRIPTION,
            Repository suggestions for starting a Copilot agent session.
            When no query is provided, returns the viewer's top contributed repositories.
            When a query is provided, returns matching repositories filtered by the same access criteria.
          DESCRIPTION
          required_capabilities: [:copilot_agents] do
            argument :query,
              String,
              "Search query to filter results. Supports free text and owner/repo format.",
              required: false
            argument :current_repository_id,
              ID,
              "Global relay ID of a repository to prioritize at the top of results.",
              required: false
            argument :limit,
              Integer,
              "How many repositories to return.",
              default_value: 10,
              required: false
          end

        def viewer_copilot_agent_repository_suggestions(query: nil, current_repository_id: nil, limit: 10)
          return [] unless is_viewer

          raise Errors::ArgumentError, "Limit must be between 1 and 30" unless limit.between?(1, 30)

          copilot_agent_repository_suggestions(
            viewer: @context[:viewer],
            cap_filter: @context[:cap_filter],
            query: query.to_s.strip,
            current_repository_id: current_repository_id,
            limit: limit,
          )
        end

        field :viewer_copilot_chat_repository_suggestions, [Objects::Repository],
          description: <<~DESCRIPTION, null: false, required_capabilities: [:copilot_agents] do
            Repository suggestions for Copilot Chat, ranked by relevance to the viewer and filtered by the provided query.
            When no query is provided, returns the viewer's top repositories ordered by contribution rank.
            When a query is provided, returns search results merged with matching top repositories.
          DESCRIPTION

          argument :query, String,
            "Search query to filter results. Supports free text and owner/repo format.",
            required: false
          argument :current_repository_id, ID,
            "Global relay ID of a repository to prioritize at the top of results.",
            required: false
          argument :owner, String,
            "Scope results to repositories owned by this user or organization login.",
            required: false
          argument :include_forks, Boolean,
            "Whether to include forked repositories in search results.",
            required: false, default_value: false
          argument :limit, Integer,
            "How many repositories to return.",
            default_value: 10, required: false
        end

        def viewer_copilot_chat_repository_suggestions(**arguments)
          return [] unless is_viewer

          limit = arguments[:limit] || 10
          raise Errors::ArgumentError, "Limit must be between 1 and 30" unless limit.between?(1, 30)

          if arguments[:owner] && arguments[:include_forks]
            raise Platform::Errors::ArgumentError, "Cannot specify both owner and include_forks arguments"
          end

          copilot_chat_repository_suggestions(arguments, limit: limit)
        end

        field :viewer_copilot_agent_sessions,
          Connections::CopilotAgentSession,
          null: true,
          description: "Lists all Copilot Agent Sessions for the viewer",
          extras: [:lookahead],
          connection: false,
          required_capabilities: [:copilot_agents] do
          has_connection_arguments

          argument :order_by,
            Inputs::CopilotAgentSessionOrder,
            "How to order the returned sessions.",
            required: false,
            default_value: { field: "LAST_UPDATED_AT", direction: "DESC" }

          argument :filter_by,
            Inputs::CopilotAgentSessionFilter,
            "Filter sessions by specific criteria.",
            required: false
        end

        def viewer_copilot_agent_sessions(
          first: nil,
          last: nil,
          after: nil,
          before: nil,
          order_by: nil,
          filter_by: nil,
          lookahead: nil
        )
          return unless is_viewer

          ConnectionWrappers::CopilotAgentSessionQuery.new(
            user: @context[:viewer],
            token: decrypted_capi_token,
            first:,
            last:,
            after:,
            before:,
            order_by:,
            filter_by:,
            field: lookahead&.field
          )
        end

        field :viewer_copilot_agent_session,
          Objects::CopilotAgentSession,
          null: true,
          description: "Fetches a specific Copilot Agent Session for the viewer.",
          required_capabilities: [:copilot_agents] do
            argument :session_id,
              String,
              "The Copilot Agent session identifier to fetch.",
              required: true
          end

        def viewer_copilot_agent_session(session_id:)
          return nil unless is_viewer

          session = CopilotSessions::AgentSession.for_session(
            user: @context[:viewer],
            session_id: session_id,
            entry_point: :agent_session_for_user_via_graphql_single,
            token: decrypted_capi_token
          )

          session || raise(Errors::NotFound, "Could not resolve to a Copilot Agent session with the ID of '#{session_id}'.")
        end

        field :repository_custom_agents,
          Connections.define(Objects::CopilotCustomAgent),
          null: false,
          description: "Lists custom agents for a repository",
          connection: true,
          required_capabilities: [:copilot_agents] do
            argument :owner,
              String,
              "Repository owner display name",
              required: true
            argument :name,
              String,
              "Repository name",
              required: true
          end

        def repository_custom_agents(owner:, name:)
          return ArrayWrapper.new([]) unless is_viewer

          if @context[:viewer].feature_flag_enabled?(:copilot_swe_agent_use_subagents, default: false)
            return process_custom_agents(owner, name)
          end

          # rubocop:disable GitHub/DoNotAllowLogin
          Platform::Helpers::RepositoryByNwo.async_repo_and_owner("#{owner}/#{name}", true).then do |repository, repo_owner|
            # rubocop:enable GitHub/DoNotAllowLogin
            next ArrayWrapper.new([]) unless repository

            if repository.feature_flag_enabled?(:copilot_swe_agent_use_subagents, default: false)
              next process_custom_agents(owner, name, repository: repository)
            end

            if repo_owner&.feature_flag_enabled?(:copilot_swe_agent_use_subagents, default: false)
              next process_custom_agents(owner, name, repository: repository)
            end

            ArrayWrapper.new([])
          end
        end

        def process_custom_agents(owner, name, repository: nil)
          token = Copilot::DecryptedToken.from(@context[:request_token].to_s)
          staging_env = CopilotSweAgent::SweAgentPath.resolve_env(user: @context[:viewer], repository: repository)

          custom_agents = CopilotSweAgent::CustomAgent.for_repository(
            user: @context[:viewer],
            repo_owner: owner,
            repo_name: name,
            token: token,
            user_session: @context[:user_session],
            staging_env:,
          )

          ArrayWrapper.new(custom_agents)
        rescue CopilotAPI::NotFoundError
          ArrayWrapper.new([])
        end

        field :viewer_copilot_agent_tasks,
          Connections::CopilotAgentTask,
          null: true,
          description: "Lists all Copilot Agent Tasks for the viewer",
          extras: [:lookahead],
          connection: false,
          required_capabilities: [:copilot_agents] do
          has_connection_arguments

          argument :order_by,
            Inputs::CopilotAgentTaskOrder,
            "How to order the returned tasks.",
            required: false,
            default_value: { field: "LAST_UPDATED_AT", direction: "DESC" }

          argument :filter_by,
            Inputs::CopilotAgentTaskFilter,
            "Filter tasks by specific criteria.",
            required: false
        end

        def viewer_copilot_agent_tasks(
          first: nil,
          last: nil,
          after: nil,
          before: nil,
          order_by: nil,
          filter_by: nil,
          lookahead: nil
        )
          return unless is_viewer

          ConnectionWrappers::CopilotAgentTaskQuery.new(
            user: @context[:viewer],
            token: decrypted_capi_token,
            first:,
            last:,
            after:,
            before:,
            order_by:,
            filter_by:,
            field: lookahead&.field
          )
        end

        field :viewer_copilot_agent_task,
          Objects::CopilotAgentTask,
          null: true,
          description: "Fetches a specific Copilot Agent Task for the viewer." do
            argument :task_id,
              String,
              "The Copilot Agent task identifier to fetch.",
              required: true
          end

        def viewer_copilot_agent_task(task_id:)
          return nil unless is_viewer

          task = CopilotSessions::TaskApi::Task.fetch_by_id(
            user: @context[:viewer],
            id: task_id,
            entry_point: :agent_task_for_user_via_graphql_single,
            token: decrypted_capi_token
          )

          task || raise(Errors::NotFound, "Could not resolve to a Copilot Agent task with the ID of '#{task_id}'.")
        end

        private

        def is_viewer
          @object == @context[:viewer]
        end
      end
    end
  end
end
