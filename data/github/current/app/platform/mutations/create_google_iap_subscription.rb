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
      argument :product_id, String, "The product id that the user has bought through the Play Store", required: true

      field :viewer, Objects::User, "The viewer performing the mutation.", null: true

      # The result of a possible Copilot individual subscription. This will be `nil` if the user does not have an
      # active Copilot subscription on the Google side. Otherwise we try to create an individual Copilot subscription
      # for the user.
      field :copilot,
        Objects::InAppPurchaseSubscriptionResult,
        "The result of the Copilot subscription.",
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

      def resolve(purchase_token:, product_id:)
        check_restrictions
        subscription_response = fetch_subscription_purchase_summary(purchase_token:, product_id:)

        raise Errors::Unprocessable.new("Play Store purchase token or product id is not valid.") unless subscription_response

        unless context[:viewer].feature_enabled?(:mobile_iap_copilot_subscription)
          raise Errors::Unprocessable.new("IAP is not available.")
        end

        check_environment(subscription_response:)

        copilot = create_copilot_subscription(subscription_response:)

        {
          copilot: copilot&.serialize,
          viewer: context[:viewer]
        }
      end

      private

      sig { params(subscription_response: Mobile::Google::SubscriptionPurchaseSummary).returns(T.untyped) }
      def check_environment(subscription_response:)
        return if subscription_response.production?

        unless context[:viewer].feature_enabled?(:mobile_accept_iap_sandbox_receipts)
          raise Errors::Unprocessable.new("Google purchase token is not valid.")
        end
      end

      def check_restrictions
        if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
          raise Errors::Unprocessable.new("iAP is not available for this environment.")
        end

        if context[:viewer].is_enterprise_managed?
          raise Errors::Unprocessable.new("Enterprise managed users cannot use iAP.")
        end

        if context[:viewer].has_any_trade_restrictions?
          raise Errors::Unprocessable.new(
            ::TradeControls::Notices.notice_as_plaintext(:api_user_account_restricted_generic)
          )
        end

        if context[:viewer].has_commercial_interaction_restriction?
          raise Errors::Unprocessable.new(
            ::TradeControls::Notices.notice_as_plaintext(:trade_screening_account_restricted_generic)
          )
        end

        if context[:viewer].spammy?
          raise Errors::Unprocessable.new("Account marked as spam are not allowed for IAP.")
        end
      end

      sig do
        params(subscription_response: Mobile::Google::SubscriptionPurchaseSummary)
          .returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_copilot_subscription(subscription_response:)
        purchase_token = subscription_response.active_copilot_purchase_token
        return unless purchase_token

        result = handle_copilot_subscription(
          purchase_token:,
          environment: subscription_response.environment
        )

        if result.ok?
          Models::InAppPurchaseSubscriptionResult.success
        else
          Models::InAppPurchaseSubscriptionResult.failure(message: result.error.message)
        end
      end

      sig do
        params(
          purchase_token: String,
          environment: Mobile::Google::SubscriptionPurchaseSummary::Environment
        )
        .returns(GitHub::Result)
      end
      def handle_copilot_subscription(purchase_token:, environment:)
        copilot_user = Copilot::User.new(context[:viewer])

        if copilot_user.administrative_blocked?
          return GitHub::Result.error(Errors::Unprocessable.new("Copilot subscription is not allowed."))
        end

        # Double check the user can actually subscribe to Copilot for Individuals.
        # This check should have already been performed and sent to the client-side via the viewer's
        # viewerCanSubscribeToCopilotIndividual field value so the user flow should be prevented and we should
        # never reach this state, but also never fully trust the client and perform this check again.
        unless copilot_user.can_subscribe_to_cfi?
          return GitHub::Result.error(Errors::Unprocessable.new("User cannot subscribe to Copilot for Individuals."))
        end

        create_zuora_account!(context[:viewer]) unless context[:viewer].zuora_account?

        Copilot::LimitedUser.find_by(user_id: copilot_user.id)&.destroy
        result = copilot_user.subscribe(
          :month,
          in_app_purchase: ::Billing::Public::InAppPurchase.google(purchase_token: purchase_token)
        )

        # Make sure that we cancel the subscription after 30 minutes if we are dealing with a test environment.
        if result.ok? && environment.test?
          subscription_item = T.must(copilot_user.copilot_active_subscription_item)

          Billing::CancelInAppPurchasedSubscriptionItemJob
            .set(wait: 30.minutes)
            .perform_later(subscription_item.id)
        end

        result
      end

      # This method will raise an error if the Zuora account should be created but could not be created.
      sig { params(user: ::User).void }
      def create_zuora_account!(user)
        return if user.zuora_account?

        service = Billing::CreateCustomer.perform(
          user,
          actor: user,
          details: { omit_billing_info: true }
        )

        raise Errors::Unprocessable.new("Customer could not be created successfully.") unless service.success?

        nil
      end

      sig { params(purchase_token: String, product_id: String).returns(T.nilable(Mobile::Google::SubscriptionPurchaseSummary)) }
      def fetch_subscription_purchase_summary(purchase_token:, product_id:)
        # Nothing we can do without a purchase token or the product id
        return if purchase_token.blank? || product_id.blank?

        subscription_purchase_summary = Mobile::Google::PlayStoreService.from_config.get_subscription_purchase_summary(purchase_token:, product_id:)

        # If we don't have an active subscription return nil
        return if subscription_purchase_summary.active_copilot_purchase_token.nil?

        Mobile::Google::SubscriptionPurchaseSummary.new(environment: subscription_purchase_summary.environment, active_copilot_purchase_token: purchase_token)
      end
    end
  end
end
