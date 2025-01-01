# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateGoogleIapSubscription < Platform::Mutations::Base
      description "Creates a subscription representing an Android in-app purchase"

      required_capabilities [:mobile_only_schema_mask]
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]
      minimum_accepted_scopes ["user"]

      argument :purchase_token, String, "The purchase token associated with the in-app purchase on Play Store", required: true

      # Product ID is deprecated and not used in the current implementation. It is kept for backward compatibility.
      argument :product_id, String, "The product id that the user has bought through the Play Store", required: false

      field :viewer, Objects::User, "The viewer performing the mutation.", null: true

      # The result of a possible Copilot individual subscription. This will be `nil` if the user does not have an
      # active Copilot subscription on the Google side. Otherwise we try to create an individual Copilot subscription
      # for the user.
      field :copilot,
        Objects::InAppPurchaseSubscriptionResult,
        "The result of the Copilot subscription.",
        null: true

      # The result of a possible Copilot Pro+ individual subscription. This will be `nil` if the user does not have an
      # active Copilot Pro+ subscription on the Google side. Otherwise we try to create one for the user.
      field :copilot_pro_plus,
        Objects::InAppPurchaseSubscriptionResult,
        "The result of the Copilot Pro+ subscription.",
        null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      def resolve(purchase_token:, product_id: nil)
        subscription_response = fetch_subscription_purchase_summary(purchase_token:)

        unless subscription_response&.active_copilot_purchase_token
          raise Errors::Unprocessable.new("Play Store purchase token is not valid.")
        end
        # Note: Instantiation of this class _will_ raise errors if the user cannot make purchases
        # for the desired environment. This is expected and should be handled by the caller.
        in_app_purchasing_subscriber = Helpers::InAppPurchaseSubscriber.new(
          user: context[:viewer],
          environment: subscription_response.environment
        )

        {
          copilot: create_copilot_subscription(in_app_purchasing_subscriber:, subscription_response:)&.serialize,
          copilot_pro_plus: create_pro_plus_subscription(in_app_purchasing_subscriber:, subscription_response:)&.serialize,
          viewer: context[:viewer]
        }
      end

      private

      sig do
        params(
          in_app_purchasing_subscriber: Helpers::InAppPurchaseSubscriber,
          subscription_response: Mobile::Google::SubscriptionPurchaseSummary
        ).returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_copilot_subscription(in_app_purchasing_subscriber:, subscription_response:)
        purchase_token = subscription_response.active_copilot_purchase_token
        return unless purchase_token
        return unless subscription_response.active_copilot_sku&.copilot_pro?

        in_app_purchase = ::Billing::Public::InAppPurchase.google(purchase_token: purchase_token)
        result = in_app_purchasing_subscriber.subscribe_to_copilot_pro(in_app_purchase)

        if result.ok?
          Models::InAppPurchaseSubscriptionResult.success
        else
          Models::InAppPurchaseSubscriptionResult.failure(message: result.error.message)
        end
      end

      sig do
        params(
          in_app_purchasing_subscriber: Helpers::InAppPurchaseSubscriber,
          subscription_response: Mobile::Google::SubscriptionPurchaseSummary
        ).returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_pro_plus_subscription(in_app_purchasing_subscriber:, subscription_response:)
        purchase_token = subscription_response.active_copilot_purchase_token
        return unless purchase_token
        return unless subscription_response.active_copilot_sku&.copilot_pro_plus?

        in_app_purchase = ::Billing::Public::InAppPurchase.google(purchase_token: purchase_token)
        result = in_app_purchasing_subscriber.subscribe_to_copilot_pro_plus(in_app_purchase)

        if result.ok?
          Models::InAppPurchaseSubscriptionResult.success
        else
          Models::InAppPurchaseSubscriptionResult.failure(message: result.error.message)
        end
      end

      sig { params(purchase_token: String).returns(T.nilable(Mobile::Google::SubscriptionPurchaseSummary)) }
      def fetch_subscription_purchase_summary(purchase_token:)
        # Nothing we can do without a purchase token
        return if purchase_token.blank?

        Mobile::Google::PlayStoreService.from_config.get_subscription_purchase_summary(purchase_token:)
      end
    end
  end
end
