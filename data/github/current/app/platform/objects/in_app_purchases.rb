# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class InAppPurchases < Objects::Base
      description "In-app purchase information made by the viewer."

      required_capabilities [:mobile_only_schema_mask]

      scopeless_tokens_as_minimum

      # Currently this is only used for the user's own in-app purchases. Any attempt to view another user's
      # in-app purchase information should be denied.
      #
      # This object is marked as mobile_only and is currently only accessible via an already authorized User
      # object. We are just being extra careful here to ensure that the viewer is the user in question.
      def self.async_api_can_access?(permission, in_app_purchases)
        permission.viewer == in_app_purchases.user
      end

      # Currently this is only used for the user's own in-app purchases. Any attempt to view another user's
      # in-app purchase information should be denied.
      #
      # This object is marked as mobile_only and is currently only accessible via an already authorized User
      # object. We are just being extra careful here to ensure that the viewer is the user in question.
      def self.async_viewer_can_see?(permission, in_app_purchases)
        permission.viewer == in_app_purchases.user
      end

      field :copilot,
        Enums::AppStore,
        "The app store where Copilot for Individual license was purchased, null if not in-app purchased.",
        null: true,
        method: :async_copilot

      field :pro,
        Enums::AppStore,
        "The app store where Individual Pro license was purchased, null if not in-app purchased.",
        null: true,
        method: :async_pro
    end
  end
end
