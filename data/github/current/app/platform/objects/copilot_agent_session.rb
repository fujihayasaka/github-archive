# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotAgentSession < Objects::Base
      required_capabilities [:copilot_agents]

      description "Represents a Copilot Agent working on a specific task."

      # Bypass authz, at the object level, for now, since SweAgent will perform its own authz checks.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Bypass authz, at the object level, for now, since SweAgent will perform its own authz checks.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      # This is the assigned UUID from SweAgent. This is meant to be transparent and not to be confused with "id"
      # will be the globally unique identifier for the session. This of this as the equivalent of
      # PullRequest#databaseId or Issue#databaseId.
      field :session_id,
        String,
        "The unique identifier of the session.",
        null: false,
        method: :id

      field :name,
        String,
        "The name of the session.",
        null: false

      field :state,
        Enums::CopilotAgentSessionState,
        "Agent's current state.",
        null: false

      field :created_at,
        Scalars::DateTime,
        "Identifies the date and time when the agent was first created.",
        null: false

      field :last_updated_at,
        Scalars::DateTime,
        "Identifies the date and time when the agent last made progress.",
        null: true

      field :completed_at,
        Scalars::DateTime,
        "Identifies the date and time when the agent finished its work.",
        null: true

      field :resource,
        Unions::CopilotAgentResource,
        "The output of the session.",
        null: true,
        method: :async_resource
    end
  end
end
