# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MobileCopilotPaywallProductFeature < Platform::Objects::Base
      description "Represents a feature included in a Copilot plan."
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

      field :title, String, "The title of the feature", null: false
    end
  end
end
