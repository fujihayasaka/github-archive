# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotPaywall < Platform::Objects::Base
      docs_category :copilot
      description "Represents the paywall configuration for Copilot on mobile."
      required_capabilities [:mobile_only_schema_mask]

      # All paywall objects are behind the mobile only schema mask,
      # and require no special permissions to access. All mobile users can see them.
      def self.async_api_can_access?(permission, push)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Returns `true` because the mobile schema mask is required to access this object.
      # The data returned is the same for all users, so we don't need to check permissions
      def self.async_viewer_can_see?(permission, push)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :paywall_products, [Objects::MobileCopilotPaywallProduct], "List of available Copilot paywall products", null: false

      field :disclaimers, [String], "List of disclaimer texts for mobile offerings and additional premium requests", null: false

      field :all_features, [Objects::MobileCopilotPaywallFeatureComparisonSection], "Comprehensive list of all features organized by sections", null: false
    end
  end
end
