# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotCustomAgent < Objects::Base
      required_capabilities [:copilot_agents]

      description "Represents a Copilot custom agent."

      # Bypass authz, at the object level, for now, since the field will perform its own authz checks.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Bypass authz, at the object level, for now, since the field will perform its own authz checks.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :name,
        String,
        "The name of the custom agent.",
        null: false

      field :description,
        String,
        "The description of the custom agent.",
        null: true

      field :display_name,
        String,
        "The display name of the custom agent.",
        null: false
    end
  end
end
