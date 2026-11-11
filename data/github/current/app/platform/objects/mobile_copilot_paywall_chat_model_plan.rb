# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotPaywallChatModelPlan < Platform::Objects::Base
      description "Represents a plan with its available chat models."
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

      field :copilot_license_type, Enums::CopilotLicenseType, "The license type for this plan", null: false

      field :title, String, "The title of the plan", null: false

      field :models, [Objects::MobileCopilotPaywallChatModel], "List of chat models available for this plan", null: false
    end
  end
end
