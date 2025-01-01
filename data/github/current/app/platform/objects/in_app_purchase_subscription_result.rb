# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class InAppPurchaseSubscriptionResult < Base
      description "Represents the result in-app purchase subscription attempt."

      mobile_only true

      field :success, Boolean, "Whether or not the subscription was successful", null: false

      field :message, String, "The message for the subscription", null: false

      def self.async_api_can_access?(*)
        # No special API permissions
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(*)
        # No special API permissions
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end
    end
  end
end
