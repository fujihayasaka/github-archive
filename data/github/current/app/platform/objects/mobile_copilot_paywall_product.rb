# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotPaywallProduct < Platform::Objects::Base
      docs_category :copilot
      description "Represents a Copilot product available on mobile."
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

      field :title, String, "The title of the plan", null: false

      field :subtitle, String, "The subtitle or description of the plan", null: true

      field :features_header, String, "Header text for what's included in the plan", null: false

      field :copilot_license_type, Enums::CopilotLicenseType, "The license type identifier used by mobile apps", null: false

      field :features, [Objects::MobileCopilotPaywallProductFeature], "List of features included in this plan", null: false
    end
  end
end
