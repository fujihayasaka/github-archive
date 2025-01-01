# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateAppleIapSubscriptions < Platform::Mutations::Base

      description "Creates subscriptions from Apple IAP receipts."

      mobile_only true

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
        check_restrictions

        subscription_summary = fetch_subscription_summary(receipt)
        raise Errors::Unprocessable.new("Apple receipt is not valid.") unless subscription_summary

        check_sandbox(subscription_summary:)

        pro = create_pro_plan_subscription(receipt:, subscription_summary:)
        copilot = create_copilot_subscription(subscription_summary:)

        {
          pro: pro&.serialize,
          copilot: copilot&.serialize,
          viewer: context[:viewer]
        }
      end

      private

      def check_restrictions
        raise Errors::Unprocessable.new("iAP is not available for this environment.") unless GitHub.iap_enabled?

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

      sig { params(subscription_summary: Mobile::Apple::SubscriptionSummary).returns(T.untyped) }
      def check_sandbox(subscription_summary:)
        return if subscription_summary.production?

        unless context[:viewer].feature_enabled?(:mobile_accept_iap_sandbox_receipts)
          raise Errors::Unprocessable.new("Apple receipt is not valid.")
        end
      end

      sig do
        params(subscription_summary: Mobile::Apple::SubscriptionSummary)
          .returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_copilot_subscription(subscription_summary:)
        unless context[:viewer].feature_enabled?(:mobile_iap_copilot_subscription)
          raise Errors::Unprocessable.new("IAP is not available.")
        end

        original_transaction_id = subscription_summary.active_copilot_original_transaction_id
        return unless original_transaction_id

        result = handle_copilot_subscription(
          original_transaction_id:,
          environment: subscription_summary.environment
        )

        if result.ok?
          Models::InAppPurchaseSubscriptionResult.success
        else
          Models::InAppPurchaseSubscriptionResult.failure(message: result.error.message)
        end
      end

      sig do
        params(
          receipt: String,
          subscription_summary: Mobile::Apple::SubscriptionSummary
        )
        .returns(T.nilable(Models::InAppPurchaseSubscriptionResult))
      end
      def create_pro_plan_subscription(receipt:, subscription_summary:)
        original_transaction_id = subscription_summary.active_pro_original_transaction_id

        return unless original_transaction_id

        handle_pro_plan_subscription(
          receipt:,
          original_transaction_id:,
          environment: subscription_summary.environment
        )

        Models::InAppPurchaseSubscriptionResult.success
      rescue Errors::Unprocessable => ex
        Models::InAppPurchaseSubscriptionResult.failure(message: ex.message)
      end

      sig do
        params(
          original_transaction_id: String,
          environment: Mobile::Apple::AppStoreClient::Environment
        )
        .returns(GitHub::Result)
      end
      def handle_copilot_subscription(original_transaction_id:, environment:)
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

        result = copilot_user.subscribe(
          :month,
          in_app_purchase: ::Billing::Public::InAppPurchase.apple(original_transaction_id: original_transaction_id)
        )

        # Make sure that we cancel the subscription after 30 minutes if we are dealing with a sandbox receipt.
        if result.ok? && environment.sandbox?
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

      sig do
        params(
          receipt: String,
          original_transaction_id: String,
          environment: Mobile::Apple::AppStoreClient::Environment
        )
        .returns(T.untyped)
      end
      def handle_pro_plan_subscription(receipt:, original_transaction_id:, environment:)
        if Billing::PlanSubscription.exists?(apple_transaction_id: original_transaction_id)
          raise Errors::Unprocessable.new("This Apple subscription is already tied to another GitHub account.")
        end

        account = context[:viewer]
        account.seats = 0
        account.plan_duration = User::BillingDependency::MONTHLY_PLAN
        account.plan = GitHub::Plan.pro
        plan_was = account.plan_was

        if account.disabled?
          account.disabled = false
        end

        raise Errors::Unprocessable.new("Account invalid.") unless account.save

        create_zuora_account!(account) unless account.zuora_account?

        if environment.production?
          if account.plan_subscription
            account.plan_subscription.update(
              apple_receipt_id: receipt,
              apple_transaction_id: original_transaction_id
            )

            account.plan_subscription.synchronize_later
          else
            # after_commit that ends up calling SynchronizePlanSubscriptionJob.perform
            account.create_plan_subscription!(
              customer: account.customer,
              apple_receipt_id: receipt,
              apple_transaction_id: original_transaction_id
            )
          end
        else # sandbox
          # do not synchronize sandbox plan subscription with Zuora
          if account.plan_subscription
            account.plan_subscription.update(
              apple_receipt_id: receipt,
              apple_transaction_id: original_transaction_id
            )
          else
            plan_subscription = account.build_plan_subscription(
              customer: account.reload.customer,
              apple_receipt_id: receipt,
              apple_transaction_id: original_transaction_id
            )

            plan_subscription.skip_synchronize_later = true
            plan_subscription.save!
          end

          # This plan change handles cancelling IAP sandbox subscriptions, Apple sandbox subscriptions are only
          # valid for 5mins but automatically renew 6 times.
          Billing::SchedulePlanChange.run(
            account: account,
            actor: account,
            plan: GitHub::Plan.free.to_s,
            active_on: Time.zone.today,
            schedule_at: Time.zone.now + 30.minutes
          )
        end

        account.track_plan_change(account, plan_was)
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
