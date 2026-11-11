# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotAgentTask < Objects::Base
      required_capabilities [:copilot_agents]

      description "Represents the resource and its associated Copilot sessions."

      # Bypass authz, at the object level, for now, since SweAgent will perform its own authz checks.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Bypass authz, at the object level, for now, since SweAgent will perform its own authz checks.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :task_id,
        String,
        "The unique identifier of the task.",
        null: false,
        method: :id

      field :title,
        String,
        "The title of the task.",
        null: true

      field :state,
        Enums::CopilotAgentSessionState,
        "Agent's current state.",
        null: false,
        method: :status

      field :last_updated_at,
        Scalars::DateTime,
        "Identifies the date and time when the agent last made progress.",
        null: true

      field :archived_at,
        Scalars::DateTime,
        "Identifies the date and time when the task was archived.",
        null: true

      field :repository,
        Repository,
        "The repository this Task was assigned to.",
        null: true,
        method: :async_repository

      field :resources,
        [Unions::CopilotAgentResource],
        "The output of the session.",
        null: false

      def resources
        resources = []

        if object.pull_request?
          resources << Platform::Loaders::ActiveRecord.load(::PullRequest, object.pull_request_id)
        end

        ArrayWrapper.new(resources)
      end

      field :session_count,
        Integer,
        "The number of Copilot Agent Sessions working or have worked on this resource.",
        null: false
    end
  end
end
