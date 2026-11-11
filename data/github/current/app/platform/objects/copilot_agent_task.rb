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

      field :state,
        Enums::CopilotAgentSessionState,
        "Agent's current state.",
        null: false

      field :last_updated_at,
        Scalars::DateTime,
        "Identifies the date and time when the agent last made progress.",
        null: true

      field :resources,
        [Unions::CopilotAgentResource],
        "The output of the session.",
        null: false

      def resources
        # Right now, CAPI has a 1:1 Task:Resource design. Let's honor that within the domain, for now, but
        # let the schema try to reduce friction by starting this out as a 1:Many relationship.
        object.async_resource.then do |resource|
          resource ? ArrayWrapper.new([resource]) : ArrayWrapper.new([])
        end
      end

      field :session_count,
        Integer,
        "The number of Copilot Agent Sessions working or have worked on this resource.",
        null: false

      field :sessions,
        [Objects::CopilotPartialAgentSession],
        "Copilot Agents which are currently and/or previously have worked on this resource.",
        null: false
    end
  end
end
