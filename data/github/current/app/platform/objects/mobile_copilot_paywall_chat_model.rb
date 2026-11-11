# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotPaywallChatModel < Platform::Objects::Base
      docs_category :copilot
      description "Represents a chat model available in Copilot."
      required_capabilities [:mobile_only_schema_mask]

      # All paywall objects are behind the mobile only schema mask,
      # and require no special permissions to access. All mobile users can see them.
      def self.async_api_can_access?(permission, push)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(permission, push)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :title, String, "The name/title of the chat model", null: false
    end
  end
end
