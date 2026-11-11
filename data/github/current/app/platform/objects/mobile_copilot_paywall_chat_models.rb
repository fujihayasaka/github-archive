# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotPaywallChatModels < Platform::Objects::Base
      description "Represents chat models information for Copilot plans."
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

      field :title, String, "The title for the chat models section", null: false

      field :plans, [Objects::MobileCopilotPaywallChatModelPlan], "List of plans with their available chat models", null: false
    end
  end
end
