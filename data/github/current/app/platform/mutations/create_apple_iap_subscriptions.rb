# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateAppleIapSubscriptions < Platform::Mutations::Base
      description "Creates subscriptions from Apple IAP receipts."

      required_capabilities [:mobile_only_schema_mask]

      visibility :public, environments: [:dotcom]

      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user"]

      argument :receipt,
        String,
        "The base64 encoded receipt for the Apple in-app purchase.",
        required: true

      # The result of a possible pro plan subscription creation. This will be `nil` if the user does not have an
      # active Pro subscription on the Apple side. Otherwise we try to create a Pro subscription.
      field :pro,
        Objects::InAppPurchaseSubscriptionResult,
        "The result of the Pro plan subscription.",
        null: true

      # The result of a possible Copilot individual subscription. This will be `nil` if the user does not have an
      # active Copilot subscription on the Apple side. Otherwise we try to create an individual Copilot subscription
      # for the user.
      field :copilot,
        Objects::InAppPurchaseSubscriptionResult,
        "The result of the Copilot subscription.",
        null: true

      # The result of a possible Copilot individual subscription. This will be `nil` if the user does not have an
      # active Copilot Pro+ subscription on the Apple side. Otherwise we try to create an individual Copilot Pro+ subscription
      # for the user.
      field :copilot_pro_plus,
        Objects::InAppPurchaseSubscriptionResult,
        "The result of the Copilot Pro+ subscription.",
        null: true

      field :viewer, Objects::User, "The viewer performing the mutation.", null: true

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

      def resolve(receipt:)
        subscription_summary = fetch_subscription_summary(receipt)
        raise Errors::Unprocessable.new("Apple receipt is not valid.") unless subscription_summary

        # Note: Instantiation of this class _will_ raise errors if the user cannot make purchases
        # for the desired environment. This is expected and should be handled by the caller.
        in_app_purchasing_subscriber = Helpers::InAppPurchaseSubscriber.new(
          user: context[:viewer],
          environment: subscription_summary.environment
        )

        pro = create_pro_plan_subscription(in_app_purchasing_subscriber:, receipt:, subscription_summary:)
        copilot = create_copilot_subscription(in_app_purchasing_subscriber:, subscription_summary:)
        copilot_pro_plus = create_copilot_pro_plus_subscription(in_app_purchasing_subscriber:, subscription_summary:)

        {
          pro: pro&.serialize,
          copilot: copilot&.serialize,
          copilot_pro_plus: copilot_pro_plus&.serialize,
          viewer: context[:viewer]
        }
      end

      private

      sig do
        params(
          in_app_purchasing_subscriber: Helpers::InAppPurchaseSubscriber,
          subscription_summary: Mobile::Apple::SubscriptionSummary
        ).returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_copilot_subscription(in_app_purchasing_subscriber:, subscription_summary:)
        original_transaction_id = subscription_summary.active_copilot_original_transaction_id
        return unless original_transaction_id

        in_app_purchase = ::Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)
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
          subscription_summary: Mobile::Apple::SubscriptionSummary
        ).returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_copilot_pro_plus_subscription(in_app_purchasing_subscriber:, subscription_summary:)
        original_transaction_id = subscription_summary.active_copilot_pro_plus_original_transaction_id
        return unless original_transaction_id

        in_app_purchase = ::Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)
        result = in_app_purchasing_subscriber.subscribe_to_copilot_pro_plus(in_app_purchase)

        if result.ok?
          Models::InAppPurchaseSubscriptionResult.success
        else
          Models::InAppPurchaseSubscriptionResult.failure(message: result.error.message)
        end
      end

      sig do
        params(
          in_app_purchasing_subscriber: Helpers::InAppPurchaseSubscriber,
          receipt: String,
          subscription_summary: Mobile::Apple::SubscriptionSummary
        )
        .returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_pro_plan_subscription(in_app_purchasing_subscriber:, receipt:, subscription_summary:)
        original_transaction_id = subscription_summary.active_pro_original_transaction_id
        return unless original_transaction_id

        in_app_purchasing_subscriber.subscribe_to_github_pro(receipt:, original_transaction_id:)

        Models::InAppPurchaseSubscriptionResult.success
      rescue Errors::Unprocessable => ex
        Models::InAppPurchaseSubscriptionResult.failure(message: ex.message)
      end

      sig { params(receipt: String).returns(T.nilable(Mobile::Apple::SubscriptionSummary)) }
      def fetch_subscription_summary(receipt)
        return if receipt.blank?

        # This is in place to help aid in codespace/local/dev testing. If you run the server with
        # APPLE_SKIP_RECEIPT_VALIDATION=true then you can pass in a JSON-serialized SubscriptionSummary object
        # and that will be used to complete the local transaction, such as:
        #   - Prod. Pro & Copilot: { "active_pro_original_transaction_id": "abc", active_copilot_original_transaction_id: "zyx" }
        #   - Prod. Pro: { "active_pro_original_transaction_id": "abc" }
        #   - Sandbox Copilot: { "environment": "Sandbox", active_copilot_original_transaction_id: "zyx" }
        #
        # If you do run the server without this environment override then the receipt will be validated against Apple's servers
        # using the Mobile::Apple::AppStoreService#from_config client below.
        return Mobile::Apple::SubscriptionSummary.deserialize(receipt) if GitHub.apple_skip_receipt_validation

        begin
          transaction_id = AppleAppStore::ReceiptDecoder
            .parse(base64_encoded_receipt: receipt)
            .first
            &.original_transaction_id
        rescue AppleAppStore::ReceiptDecoder::DecodeError, OpenSSL::ASN1::ASN1Error => ex
          return
        end

        return unless transaction_id

        Mobile::Apple::AppStoreService.from_config.get_subscription_summary(
          original_transaction_id: transaction_id
        )
      end
    end
  end
end
