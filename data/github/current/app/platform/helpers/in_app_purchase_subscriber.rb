# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    # This class is responsible for handling in-app purchases for subscriptions.
    # It is a composite class that wraps up a user and an environment and knows how to make the correct
    # calls, within our domain, to create subscriptions.
    #
    # Note: Instantiation _can_ raise errors if the user cannot make purchases. Reasons can be: user is spammy,
    # trade-resricted, enterprise managed, etc. This is expected and should be handled by the caller.
    class InAppPurchaseSubscriber
      Environment = T.type_alias do
        T.any(
          Mobile::Apple::AppStoreClient::Environment,
          Mobile::Google::SubscriptionPurchaseSummary::Environment
        )
      end

      sig { returns(User) }
      attr_reader :user

      sig { returns(Environment) }
      attr_reader :environment

      sig do
        params(user: User, environment: Environment).void
      end
      def initialize(user:, environment:)
        @user = user
        @environment = environment

        assert_user_can_subscribe!
      end

      sig { params(in_app_purchase: ::Billing::Public::InAppPurchase).returns(GitHub::Result) }
      def subscribe_to_copilot_pro(in_app_purchase)
        subscribe_to_copilot(in_app_purchase, "pro")
      end

      sig do
        params(in_app_purchase: ::Billing::Public::InAppPurchase).returns(GitHub::Result)
      end
      def subscribe_to_copilot_pro_plus(in_app_purchase)
        subscribe_to_copilot(in_app_purchase, "pro_plus")
      end

      sig do
        params(in_app_purchase: ::Billing::Public::InAppPurchase).returns(GitHub::Result)
      end
      def subscribe_to_copilot_max(in_app_purchase)
        subscribe_to_copilot(in_app_purchase, "max")
      end

      # Currently only Apple's App Store can purchase GitHub Pro plans.
      sig { params(receipt: String, original_transaction_id: String).returns(T.untyped) }
      def subscribe_to_github_pro(receipt:, original_transaction_id:)
        if Billing::PlanSubscription.exists?(apple_transaction_id: original_transaction_id)
          raise Errors::Unprocessable.new("This Apple subscription is already tied to another GitHub account.")
        end

        account = user
        account.seats = 0
        account.plan_duration = User::BillingDependency::MONTHLY_PLAN
        account.plan = GitHub::Plan.pro
        plan_was = account.plan_was

        raise Errors::Unprocessable.new("Account invalid.") unless account.save

        force_unlock = !user.feature_flag_enabled?(:billing_do_not_force_unlock_during_in_app_purchase, default: false)
        ensure_billing_unlocked("github_pro", force: force_unlock)
        ensure_zuora_account_exists!

        if environment.production?
          if account.plan_subscription
            T.must(account.plan_subscription).update(
              apple_receipt_id: receipt,
              apple_transaction_id: original_transaction_id
            )

            T.must(account.plan_subscription).synchronize_later
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
            T.must(account.plan_subscription).update(
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

      private

      sig do
        params(
          in_app_purchase: ::Billing::Public::InAppPurchase,
          sku: String
        ).returns(T.nilable(GitHub::Result))
      end
      def validate_user_can_subscribe_to_copilot(in_app_purchase, sku)
        copilot_user = Copilot::User.new(user)

        if sku == "pro" && !copilot_user.can_subscribe_to_cfi?
          # Double check the user can actually subscribe to Copilot for Individuals.
          # This check should have already been performed and sent to the client-side via the viewer's
          # viewerCanSubscribeToCopilotIndividual field value so the user flow should be prevented and we should
          # never reach this state, but also never fully trust the client and perform this check again.
          return unprocessable_error_result("User cannot subscribe to Copilot for Individuals.")
        elsif sku == "pro_plus"
          if copilot_user.has_pro_plus_access?
            return unprocessable_error_result("User already has an active Copilot Pro+ subscription.")
          end

          active_subscription = copilot_user.copilot_active_subscription_item

          # If the user has an active CfI Pro subscription, then it must be from the same store as the new subscription.
          # Otherwise, CfI Pro and CfI Pro+ have the same eligibility requirements.
          if in_app_purchase.type == ::Billing::Public::InAppPurchase::Type::Apple &&
            active_subscription &&
            !active_subscription.apple_in_app_purchase?

            return unprocessable_error_result("User already has a Copilot subscription that is not managed through the Apple App Store.")
          elsif in_app_purchase.type == ::Billing::Public::InAppPurchase::Type::Google &&
            active_subscription &&
            !active_subscription.google_in_app_purchase?

            return unprocessable_error_result("User already has a Copilot subscription that is not managed through the Google Play Store.")
          elsif !active_subscription && !copilot_user.can_subscribe_to_cfi?
            return unprocessable_error_result("User cannot subscribe to Copilot Pro+.")
          end
        end

        nil
      end

      sig { params(in_app_purchase: ::Billing::Public::InAppPurchase, sku: String).returns(GitHub::Result) }
      def subscribe_to_copilot(in_app_purchase, sku)
        copilot_user = Copilot::User.new(user)

        if copilot_user.administrative_blocked?
          return unprocessable_error_result("Copilot subscription is not allowed.")
        end

        # If we get back any non-null result then we have a validation error, return it immediately.
        validation_result = validate_user_can_subscribe_to_copilot(in_app_purchase, sku)
        return validation_result if validation_result

        ensure_billing_unlocked("copilot_#{sku}")
        ensure_zuora_account_exists!
        ensure_limited_user_does_not_exist

        result =
          if sku == "pro"
            copilot_user.subscribe(:month, in_app_purchase:)
          elsif sku == "pro_plus"
            copilot_user.subscribe_pro_plus(:month, in_app_purchase:)
          elsif sku == "max" && copilot_user.feature_flag_enabled?(:copilot_iap_max_sku, default: false)
            copilot_user.subscribe_max(:month, in_app_purchase:)
          else
            unprocessable_error_result("Unhandled SKU: #{sku}")
          end

        # Make sure that we cancel the subscription after 30 minutes if we are dealing with a sandbox receipt.
        cancel_copilot_after_30_minutes if result.ok? && environment.cancel_after_30_minutes?

        result
      end

      sig { void }
      def cancel_copilot_after_30_minutes
        copilot_user = Copilot::User.new(user)

        subscription_item = T.must(copilot_user.copilot_active_subscription_item)

        Billing::CancelInAppPurchasedSubscriptionItemJob
          .set(wait: 30.minutes)
          .perform_later(subscription_item.id)
      end

      sig { void }
      def assert_user_can_subscribe!
        assert_correct_environments!
        assert_user_has_no_restrictions!
      end

      sig { void }
      def assert_correct_environments!
        # environment here represents the environment of the in-app purchase as sent to us by Apple or Google.
        # We only allow users with this FF to test in the sandbox environments for Apple and Google.
        if !environment.production? && !user.feature_flag_enabled?(:mobile_accept_iap_sandbox_receipts, default: false)
          raise Errors::Unprocessable.new("Invalid environment.")
        end

        # If GitHub's environment does not support IAP then we should not process the request.
        if !GitHub.iap_enabled?
          raise Errors::Unprocessable.new("iAP is not available for this environment.")
        end
      end

      sig { void }
      def assert_user_has_no_restrictions!
        if user.is_enterprise_managed?
          raise Errors::Unprocessable.new("Enterprise managed users cannot use iAP.")
        end

        if user.has_any_trade_restrictions?
          raise Errors::Unprocessable.new(
            ::TradeControls::Notices.notice_as_plaintext(:api_user_account_restricted_generic)
          )
        end

        if user.has_commercial_interaction_restriction?
          raise Errors::Unprocessable.new(
            ::TradeControls::Notices.notice_as_plaintext(:trade_screening_account_restricted_generic)
          )
        end

        if user.spammy?
          raise Errors::Unprocessable.new("Account marked as spam are not allowed for IAP.")
        end
      end

      sig { params(message: String).returns(GitHub::Result) }
      def unprocessable_error_result(message)
        GitHub::Result.error(Errors::Unprocessable.new(message))
      end

      sig { void }
      def ensure_limited_user_does_not_exist
        Copilot::LimitedUser.find_by(user_id: user.id)&.destroy
      end

      # This method will raise an error if the Zuora account should be created but could not be created.
      sig { void }
      def ensure_zuora_account_exists!
        return if user.zuora_account?

        service = Billing::CreateCustomer.perform(
          user,
          actor: user,
          details: { omit_billing_info: true }
        )

        Kernel.raise(Errors::Unprocessable.new("Customer could not be created successfully.")) unless service.success?

        nil
      end

      sig { params(product: String, force: T::Boolean).void }
      def ensure_billing_unlocked(product, force: false)
        return unless user.disabled?

        GitHub.dogstats.increment("billing.in_app_purchase_subscriber.ensure_billing_unlocked", tags: ["product:#{product}"])

        payload = {
          "code.namespace" => "Platform::Helpers::InAppPurchaseSubscriber",
          "code.function" => __method__,
          "gh.billing.billable_entity.balance" => user.balance,
          "gh.billing.billable_entity.billed_on" => user.billed_on,
          "gh.billing.billable_entity.billing_attempts" => user.billing_attempts,
          "gh.billing.billable_entity.external_subscription" => user.external_subscription?,
          "gh.billing.billable_entity.has_valid_payment_method" => user.has_valid_payment_method?(feature_type: :noncommercial),
          "gh.billing.billable_entity.payment_amount" => user.payment_amount,
          "gh.billing.billable_entity.plan" => user.plan.name,
          "gh.billing.billable_entity.should_disable" => user.should_disable?,
          "gh.billing.billable_entity.id" => user.id,
          "gh.billing.billable_entity.login" => user.display_login,
          "gh.billing.billable_entity.type" => user.class.name,
          "gh.billing.in_app_purchase_subscriber.product" => product,
        }

        if customer = user.customer
          payload.merge!({
            "gh.billing.customer.disabled_reasons" => customer.disabled_reasons.join(","),
            "gh.billing.customer.id" => customer.id,
            "gh.billing.customer.locked_at" => customer.locked_at,
            "gh.billing.customer.requires_manual_transactions" => customer.requires_manual_transactions?,
          })
        end

        if plan_subscription = user.plan_subscription
          payload.merge!({
            "gh.billing.plan_subscription.id" => plan_subscription.id,
            "gh.billing.plan_subscription.active_non_metered_charges?" => plan_subscription.active_non_metered_charges?,
          })
        end

        GitHub.logger.info(payload)

        if user.feature_flag_enabled?(:billing_unlock_during_in_app_purchase, default: false)
          user.remove_all_payment_methods(user)
          user.reset_billing_attempts
          user.enable!
        elsif force
          user.enable!
        end
      end
    end
  end
end
