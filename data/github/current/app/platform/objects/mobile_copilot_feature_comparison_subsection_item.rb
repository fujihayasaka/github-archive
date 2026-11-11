# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotFeatureComparisonSubsectionItem < Platform::Objects::Base
      docs_category :copilot
      description "Represents a plan-specific row in the feature comparison table."
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

      field :copilot_license_type, Enums::CopilotLicenseType, "The license type for this plan row", null: false

      field :plan_title, String, "The title of the plan this row belongs to", null: false

      field :icon, Enums::MobileCopilotPaywallIcon, "Icon identifier to display for this feature in this plan", null: false

      field :subtitle, String, "Optional subtitle text for this plan row", null: true
    end
  end
end
