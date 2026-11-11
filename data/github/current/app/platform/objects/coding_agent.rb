# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodingAgent < Objects::Base
      docs_category :copilot
      description "A coding agent that can be used to start a session"

      required_capabilities [:copilot_agents]

      # Allow the query performing authorization to control access.
      def self.async_api_can_access?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Authorization is handled by the object that returns this type.
      def self.async_viewer_can_see?(_permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :slug,
        String,
        "Unique slug identifier for the agent.",
        null: false

      field :display_name,
        String,
        "Human-readable display name for the agent.",
        null: false

      field :doc_url,
        Scalars::URI,
        "Documentation URL for the agent.",
        null: true

      field :integration_id,
        Int,
        "The integration ID of this agent.",
        null: false

      def integration_id
        @object.integration&.id
      end

      field :bot,
        Bot,
        "The bot account for this agent.",
        null: true

      def bot
        @object.integration&.async_bot
      end

      field :avatar_url,
        Scalars::URI,
        "Avatar URL for the agent.",
        null: true do
          argument :size,
            Integer,
            "The size in pixels of the resulting square image.",
            required: false
        end

      def avatar_url(size: nil)
        integration = @object.integration
        return unless integration

        integration.primary_avatar_url(size || 64)
      end

      field :is_copilot,
        Boolean,
        "Whether this agent is the GitHub Copilot agent.",
        null: false

      # We check if this agent is the Copilot agent by comparing the slug to the
      # well-known and constant Copilot SWE Agent slug.
      # This is tested to ensure it remains constant.
      def is_copilot
        @object.slug == Apps::Privileged::CopilotSWEAgent::SLUG
      end

      field :type,
        Enums::CopilotAgentType,
        "The type of agent.",
        null: false

      def type
        @object.group.serialize
      end
    end
  end
end
