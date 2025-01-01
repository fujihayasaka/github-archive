# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateMobileSubscription < Platform::Mutations::Base
      include Scientist
      extend T::Sig

      description "Creates a subscription representing a in-app purchase"

      mobile_only true
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]
      minimum_accepted_scopes ["user"]

      argument :apple_receipt, String, "The base64 encoded receipt for the apple in-app purchase", required: true

      field :success, Boolean, "Whether or not the subscription was successful", null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(apple_receipt:)
        check_restrictions

        subscription_summary = fetch_subscription_summary(apple_receipt)

        if subscription_summary && subscription_summary.pro?
          handle_pro_plan_subscription(apple_receipt:, subscription_summary:)

          { success: true }
        else
          raise Errors::Unprocessable.new("Apple receipt is not valid.")
        end
      end

      private

      def check_restrictions
        if context[:viewer].has_any_trade_restrictions?
          raise Errors::Unprocessable.new(::TradeControls::Notices.notice_as_plaintext(:api_user_account_restricted_generic))
        end

        if context[:viewer].has_commercial_interaction_restriction?
          raise Errors::Unprocessable.new(::TradeControls::Notices.notice_as_plaintext(:trade_screening_account_restricted_generic))
        end
      end

      def handle_pro_plan_subscription(apple_receipt:, subscription_summary:)
        original_transaction_id = subscription_summary.active_pro_original_transaction_id

        return unless original_transaction_id

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

        # create customer if not zuora synced
        unless account.zuora_account?
          service = Billing::CreateCustomer.perform(
            account,
            actor: context[:viewer],
            details: { omit_billing_info: true }
          )

          raise Errors::Unprocessable.new("Customer could not be created successfully.") unless service.success?
        end

        if subscription_summary.production?
          if account.plan_subscription
            account.plan_subscription.update(apple_receipt_id: apple_receipt, apple_transaction_id: original_transaction_id)
            account.plan_subscription.synchronize_later
          else
            # after_commit that ends up calling SynchronizePlanSubscriptionJob.perform
            account.create_plan_subscription!(
              customer: account.customer,
              apple_receipt_id: apple_receipt,
              apple_transaction_id: original_transaction_id
            )
          end
        else # sandbox
          # do not synchronize sandbox plan subscription with Zuora
          if account.plan_subscription
            account.plan_subscription.update(apple_receipt_id: apple_receipt, apple_transaction_id: original_transaction_id)
          else
            plan_subscription = account.build_plan_subscription(
              customer: account.reload.customer,
              apple_receipt_id: apple_receipt,
              apple_transaction_id: original_transaction_id
            )

            plan_subscription.skip_synchronize_later = true
            plan_subscription.save!
          end

          # this plan change handles canceling IAP sandbox subscriptions, apple sandbox subscriptions
          # are only valid for 5mins but automatically renew 6 times
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

      def fetch_subscription_summary(apple_receipt)
        # Nothing we can do without a receipt
        return if apple_receipt.blank?

        # Treat decoding errors as invalid receipts.
        begin
          transaction_id = AppleAppStore::ReceiptDecoder
            .parse(base64_encoded_receipt: apple_receipt)
            .first
            &.original_transaction_id
        rescue AppleAppStore::ReceiptDecoder::DecodeError, OpenSSL::ASN1::ASN1Error => ex
          return
        end

        # Nothing we can do without a transaction ID so we can treat it like an invalid receipt
        return unless transaction_id

        Mobile::Apple::AppStoreService.from_config.get_subscription_summary(
          original_transaction_id: transaction_id
        )
      end
    end
  end
end
