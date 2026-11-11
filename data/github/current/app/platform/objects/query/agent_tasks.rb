# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::AgentTasks
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :repository_agent_tasks,
      Connections::CopilotAgentTask,
      null: true,
      description: "Lists all Copilot Agent Tasks for the repository",
      extras: [:lookahead],
      connection: false,
      required_capabilities: [:copilot_agents] do
      has_connection_arguments

      argument :owner, String, "Repository owner display name", required: true
      argument :name, String, "Repository name", required: true
      argument :author, String, "Filter tasks by author login.", required: false, default_value: nil
      argument :states, [Enums::CopilotAgentSessionState], "Limit tasks to with the given states.", required: false
      argument :archived, Boolean, "Limit tasks by archived status.", required: false, default_value: nil
      argument :order_by,
        Inputs::CopilotAgentTaskOrder,
        "How to order the returned tasks.",
        required: false,
        default_value: { field: "LAST_UPDATED_AT", direction: "DESC" }
      argument :artifact_type,
        Enums::CopilotAgentArtifactType,
        "Limit tasks by artifact type.",
        required: false,
        default_value: nil
      argument :integration_slugs,
        [String],
        "Limit tasks to those created by the given integrations.",
        required: false,
        default_value: nil
    end

    def repository_agent_tasks(
      owner:,
      name:,
      author: nil,
      states: nil,
      archived: nil,
      first: nil,
      last: nil,
      after: nil,
      before: nil,
      order_by: nil,
      lookahead: nil,
      artifact_type: nil,
      integration_slugs: nil
    )
      token = Copilot::DecryptedToken.from(@context[:request_token].to_s)
      viewer = @context[:viewer]
      integration_ids = integration_ids_for_slugs(integration_slugs)

      # If the user sent in slugs to filter by BUT somehow we couldnt even find one
      # then we should return no results. This prevents us from accidentally returning all tasks when
      # given invalid slugs.
      return ConnectionWrappers::CopilotAgentTaskWrapper.empty if integration_slugs.present? && integration_ids.blank?

      # rubocop:disable GitHub/DoNotAllowLogin
      Platform::Helpers::RepositoryByNwo.async_repo_and_owner("#{owner}/#{name}", true).then do |repository, _|
        # rubocop:enable GitHub/DoNotAllowLogin
        next nil unless repository

        if author.present?
          Loaders::ActiveRecord.load(::User, author, column: :login, case_sensitive: false).then do |user|
            next ConnectionWrappers::CopilotAgentTaskWrapper.empty unless user

            build_wrapper(
              repository: repository,
              viewer: viewer,
              token: token,
              author_id: user.id,
              archived: archived,
              session_states: states,
              order_by: order_by,
              first: first,
              last: last,
              after: after,
              before: before,
              lookahead: lookahead,
              artifact_type:,
              integration_ids:
            )
          end
        else
          build_wrapper(
            repository:,
            viewer:,
            token:,
            author_id: nil,
            archived:,
            session_states: states,
            order_by:,
            first:,
            last:,
            after:,
            before:,
            lookahead:,
            artifact_type:,
            integration_ids:
          )
        end
      end
    end

    private

    # Resolves the given agent slugs to their integration ids so they can be
    # passed to the Task API as an agent id filter. Returns nil when no slugs are
    # provided. Unknown slugs are dropped, so filtering by only unknown slugs
    # yields an empty result set.
    def integration_ids_for_slugs(integration_slugs)
      return nil if integration_slugs.blank?

      integration_slugs.filter_map do |slug|
        AgenticApp.agent_for_slug(slug)&.integration&.id
      end
    end

    def build_wrapper(repository:, viewer:, token:, author_id:, archived:, session_states:, order_by:, first:, last:, after:, before:, lookahead:, artifact_type:, integration_ids:)
      sort_field = order_by&.dig(:field)&.then { |f| CopilotSessions::TaskApi::SortField.deserialize(f.downcase) }
      sort_direction = order_by&.dig(:direction)&.then { |d| CopilotSessions::SortDirection.deserialize(d.downcase) }
      session_states = session_states&.map { |s| CopilotSessions::SessionState.deserialize(s.downcase) }
      artifact_type = artifact_type ? CopilotSessions::TaskApi::ArtifactType.deserialize(artifact_type.downcase) : nil

      fetcher = ->(page, limit) do
        CopilotSessions::TaskApi::TaskList.for_repository(
          repository:,
          user: viewer,
          token:,
          owner_filter: author_id,
          archived_filter: archived,
          session_states:,
          entry_point: :agent_tasks_for_repository_via_graphql,
          page_number: page,
          page_size: limit,
          sort_field:,
          sort_direction:,
          artifact_type:,
          include_agent_ids: integration_ids
        )
      end

      ConnectionWrappers::CopilotAgentTaskWrapper.new(
        fetcher:,
        first:,
        last:,
        after:,
        before:,
        field: lookahead&.field
      )
    end
  end
end
