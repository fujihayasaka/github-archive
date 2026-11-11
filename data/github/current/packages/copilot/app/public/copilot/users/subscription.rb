# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Subscription
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Users::Signatures

      abstract!
      include Copilot::Helpers
      include Copilot::Errors

      FREE_TRIAL_ELOQUA_URI = "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1654873045572&elqSiteID=88570519"
      CANCEL_TRIAL_ELOQUA_URI = "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1660759955375&elqSiteId=88570519"
      CACHE_KEY = T.let("copilot_subscription_for_user_id_attempted_at".freeze, String)

      sig { override.returns(Symbol) }
      def subscription_type
        copilot_authorizer_object.subscription_type
      end

      sig { override.returns(T.nilable(String)) }
      def copilot_billing_type
        subscription_type.to_s
      end

      # This checks if a user has allowed copilot access
      #
      # @return [Boolean] whether the copilot Auth object allows access (skipping snippy check)
      sig { returns(T::Boolean) }
      def access_allowed?
        copilot_authorizer_object_no_snippy.access_allowed?
      end

      # This checks whether the user has signed up for Copilot
      # 1. Do they have an active/trial subscription?
      # 2. Do they have free access that they "subscribed" to?
      # @return [Boolean] whether they have already signed up (paid or free)
      sig { override.returns(T::Boolean) }
      def has_signed_up?
        GitHub.tracer.in_span("copilot.has_signed_up") do |_span|
          return true if has_free_access? # this checks for an existing FreeUser record
          return true if has_limited_access? # this checks for an existing LimitedUser record
          return true if has_educational_access? # this checks for an active EDU SKU SubscriptionItem
          return true if has_active_subscription? || has_trial_subscription?

          false
        end
      end

      # A user can view their copilot settings if:
      # 1. They can modify them (see can_modify_copilot_settings?)
      # 2. They have a seat assigned (Copilot for Business)
      sig { override.returns(T::Boolean) }
      def can_view_copilot_settings?
        return true if can_modify_copilot_settings?
        return true if copilot_organization
        return true if has_cfb_access?
        false
      end

      sig { override.returns(T::Boolean) }
      def can_modify_copilot_settings?
        return false if copilot_organization
        return true if has_signed_up?

        false
      end

      # A user can subscribe to cfi as long as they
      # 1. do not have cfi access
      # 2. do not have cfb/cfe access
      # 3. cannot sign up for free (see can_signup_for_free?)
      #
      # @return [Boolean] whether they can subsribe to cfi
      sig { returns(T::Boolean) }
      def can_subscribe_to_cfi?
        return true if has_limited_access?

        !has_cfi_access? && !has_cfb_access? && !can_signup_for_free?
      end

      sig { returns(T::Boolean) }
      def edu_signup_enabled?
        FeatureFlag.vexi.enabled?(:copilot_edu_sku_subscribe_educational, default: false) || FeatureFlag.vexi.enabled?(:copilot_edu_sku_subscribe_educational, user_object, default: false)
      end

      # A user can signup for free as long as they
      # 1. do not have an active billing subscription (including trial) and
      # 2. they have a free_user record that is not subscribed OR
      # 3. they have a redeemed student coupon
      #
      # @return [Boolean] whether they can sign up for free
      sig { override.returns(T::Boolean) }
      def can_signup_for_free?
        return false if has_active_subscription? || has_trial_subscription?
        return true if edu_signup_enabled? && can_signup_for_educational?
        return false unless free_user.present?

        !T.must(free_user).subscribed?
      end

      sig { returns(T::Boolean) }
      def has_student_coupon?
        return false unless user_object.coupon_redemption.present?
        Copilot::STUDENT_COUPON_CODES.include?(user_object.coupon_redemption&.coupon&.code)
      end

      sig { returns(T::Boolean) }
      def has_valid_student_coupon?
        coupon_redemption = user_object.coupon_redemption
        return false unless coupon_redemption.present?
        return false unless Copilot::STUDENT_COUPON_CODES.include?(coupon_redemption.coupon&.code)
        !coupon_redemption.expired?
      end

      sig { override.returns(T::Boolean) }
      def can_signup_for_educational?
        # This will return true if a user has an active paid Copilot subscription
        # but we gate signup for those users in subscribe_educational; this behavior could change if we enable downgrade
        # we exclude campus experts here because they get what other FreeUsers get (Pro)
        is_campus_expert = user_object.current_campus_expert?
        return true if edu_signup_enabled? && !active_subscription_is_edu && has_student_coupon? && !is_campus_expert

        # user has a FreeUser record but subscribed is false
        return true if free_user&.free_user_type == Copilot::FreeUser::EDUCATIONAL.name && !free_user&.subscribed?

        false
      end

      # A user can signup for limited as long as they
      # 1. do not have an active billing subscription (including trial) and
      # 2. they have a free_user record that is not subscribed
      #
      # @return [Boolean] whether they can sign up for free
      sig { override.returns(T::Boolean) }
      def can_signup_for_limited?
        return false if has_signed_up?
        return false if has_cfe_access?
        return false if has_cfb_access?

        Copilot::LimitedUser.for_subscribed_user(user_object).nil?
      end

      sig { override.returns(String) }
      def free_signup_reason
        return "" unless can_signup_for_free?
        return "" unless free_user.present?

        case T.must(free_user).free_user_type.downcase.gsub(/\s/, "_")
        when "y_combinator"
          "As a YCombinator alum, you get access to Copilot for free!"
        when "ms_mvp"
          "Thanks for being a Microsoft MVP!"
        when "github_star"
          "Thanks for being a GitHub Star!"
        when "educational", "engagedoss", "faculty"
          "Thanks for being a part of our open source and education communities."
        else
          ""
        end
      end

      # If a user has purchased a subscription in the past, but it has expired, they may still try
      # to access Copilot.
      sig { override.returns(T::Boolean) }
      def has_subscription_ended?
        # if the user has an active or trial subscription, they have not ended
        return false if has_active_subscription? || has_trial_subscription?

        all_copilot_subscription_items.any? && copilot_active_subscription_item.nil?
      end

      sig { override.returns(T::Array[::Billing::SubscriptionItem]) }
      def all_copilot_subscription_items
        # load up the subscription items without filter to see if there are ANY copilot items
        user_object.subscription_items.select do |item|
          item.subscribable.is_a?(::Billing::ProductUUID) && item.subscribable.product_type == Copilot::PRODUCT_TYPE
        end.to_a
      end

      # Checks if there was only ever a trial subscription (excluding educational SKU)
      sig { override.returns(T::Boolean) }
      def trial_only_subscription?
        items = non_edu_copilot_subscription_items
        items.any? && items.none?(&:latest_billing_transaction)
      end

      # If a user has purchased a subscription in the past, but was downgraded
      # because of 3 or more failed billing attempts
      sig { override.returns(T::Boolean) }
      def subscription_ended_due_to_billing_trouble?
        return false unless user_object.unable_to_bill?
        return false unless user_object.plan_subscription.present?

        T.must(user_object.plan_subscription).has_balance?
      end

      # This is a wrapper around the monthly and yearly checks
      #
      # @return [Boolean] whether they have an active subscription
      sig { override.returns(T::Boolean) }
      def has_active_subscription?
        has_active_monthly_subscription? || has_active_yearly_subscription?
      end

      # A user has an active monthly subscription if
      # they have a monthly SubscriptionItem and it's not in trial mode
      #
      # @return [Boolean] whether they have an active monthly subscription
      sig { override.returns(T::Boolean) }
      def has_active_monthly_subscription?
        return false unless copilot_active_subscription_item.present?
        return false if has_trial_subscription?

        T.must(copilot_active_subscription_item).monthly?
      end

      # A user has an active yearly subscription if
      # they have a yearly SubscriptionItem and it's not in trial mode
      #
      # @return [Boolean] whether they have an active yearly subscription
      sig { override.returns(T::Boolean) }
      def has_active_yearly_subscription?
        return false unless copilot_active_subscription_item.present?
        return false if has_trial_subscription?

        T.must(copilot_active_subscription_item).yearly?
      end

      # A user has a trial subscription if
      # they have a monthly or yearly SubscriptionItem and it's in trial mode
      #
      # @return [Boolean] whether they have an trial subscription
      sig { override.returns(T::Boolean) }
      def has_trial_subscription?
        return false unless copilot_active_subscription_item.present?
        return true if copilot_authorizer_object.has_cfb_trial_access? || copilot_authorizer_object.has_cfe_trial_access?

        T.must(copilot_active_subscription_item).on_free_trial?
      end

      sig { returns(T::Boolean) }
      def has_trial_access?
        has_trial_subscription?
      end

      # Eligible for trial
      #
      # @return [Boolean] whether they have access to a trial
      sig { override.returns(T::Boolean) }
      def eligible_for_trial?
        return false if user_object.disabled? || user_object.dunning?
        return false if has_active_subscription? || has_trial_subscription?
        return false if copilot_user_object.has_reached_limit_of_trial_users_sharing_payment_method?
        return false if copilot_user_object.feature_flag_enabled?(:copilot_disable_cfi_pro_trials, default: false) && !copilot_user_object.feature_flag_enabled?(:copilot_enable_cfi_pro_trials, default: false)

        ::Billing::Public::SubscriptionItem.eligible_for_free_trial?(
          product: copilot_pro_product_identifier,
          account: user_object,
        )
      end

      # This checks if a user has (or had) either an active copilot trial or subscription
      #
      # @return [Boolean] whether they ever had an active subscription
      sig { returns(T::Boolean) }
      def had_personal_subscription?
        has_active_subscription? || has_trial_subscription? || has_subscription_ended? || has_free_access? || has_limited_access?
      end

      sig { override.returns(ActiveSupport::Duration) }
      def available_trial_length
        return 0.days if !eligible_for_trial?

        Copilot.free_trial_length.days
      end

      # This method attempts to "sign up" a FreeUser
      # This means that they have agreed and configured their settings
      #
      # @return [GitHub::Result] whether they were successfully signed up
      sig { override.returns(GitHub::Result) }
      def subscribe_free_user
        if edu_signup_enabled? && can_signup_for_educational?
          GitHub.logger.info("User is eligible for educational signup", "gh.user.id" => user_object.id)
          GitHub.dogstats.increment("copilot.educational_signup.eligible")
          return subscribe_educational
        end

        GitHub::Result.new do
          unless free_user.present? && can_signup_for_free?
            Kernel.raise SignupError.new("It appears you are not eligible to sign up to GitHub Copilot for free")
          end
          T.must(free_user).subscribe
        end
      end

      # This method attempts to "sign up" a LimitedUser
      # This means that they have agreed and configured their settings
      #
      # @return [GitHub::Result] whether they were successfully signed up
      sig { override.params(skip_copilot_signup_email: T::Boolean).returns(GitHub::Result) }
      def subscribe_limited_user(skip_copilot_signup_email: false)
        GitHub::Result.new do
          result = Copilot::LimitedUser.subscribe_user(user_object, skip_copilot_signup_email:)
          return result if result.ok?

          GitHub.logger.error(
            result.error,
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "subscribe_limited_user",
            "gh.user.id" => user_object.id,
          )
          Kernel.raise Copilot::Errors::SignupError.new(result.error)
        end
      end

      # This creates or updates a subscription to Copilot Pro
      sig do
        override.params(
          duration: Symbol,
          in_app_purchase: T.nilable(::Billing::Public::InAppPurchase)
        ).returns(GitHub::Result)
      end
      def subscribe(duration, in_app_purchase: nil)
        if in_app_purchase && copilot_user_object.cfi_paid_plan_upgrade_restricted? && user_object.feature_flag_enabled?(:copilot_iap_cfi_signups_restricted, default: false)
          return GitHub::Result.error(SignupError.new("This plan for GitHub Copilot is currently not available"))
        end

        if can_signup_for_free? && free_user && !has_educational_access?
          return GitHub::Result.error(SignupError.new("It appears you are eligible for free access to GitHub Copilot"))
        end

        # In-app purchasing will control its own trial lengths within their respective App Stores along with
        # doing the Billing for us. In the case of IAP just set the trial length to 0 within our system.
        free_trial_length = in_app_purchase ? 0.days : available_trial_length

        duration_billing_cycle = if duration == :month
          ::Billing::Public::SubscriptionItems::BillingCycle::Month
        else
          ::Billing::Public::SubscriptionItems::BillingCycle::Year
        end

        # For now we have no intention of selling anything other than monthly IAP CfI subscriptions.
        if duration_billing_cycle != ::Billing::Public::SubscriptionItems::BillingCycle::Month && in_app_purchase
          return GitHub::Result.error(SignupError.new("Only monthly plans are currently supported for in-app purchasing."))
        end

        copilot_pro_product = copilot_pro_product_identifier(duration: duration_billing_cycle)
        active_subscription_item = copilot_active_subscription_item
        active_subscription_is_pro_plus = active_subscription_item && copilot_pro_plus_product_identifier.same?(active_subscription_item.product_identifier, match_billing_cycle: false)

        cancelled_copilot_pro_subscription_items = all_copilot_subscription_items.map do |item|
          product_identifier = ::Billing::Public::SubscriptionItem.new(item).product_identifier
          [item, product_identifier]
        end.select do |item, product_identifier|
          item.cancelled? && product_identifier.same?(copilot_pro_product, match_billing_cycle: false)
        end
        # A cancelled Copilot Pro Plus subscription item can't be used to reactivate Copilot Pro; reactivation is only for the same product with the same billing cycle
        has_cancelled_pro_subscription_item_with_same_billing_cycle = cancelled_copilot_pro_subscription_items.any? do |_item, product_identifier|
          product_identifier.billing_cycle == duration_billing_cycle
        end
        # Do not use the new reactivation flow for IAP since it does not currently support it.
        overage_cents = nil
        result = if has_cancelled_pro_subscription_item_with_same_billing_cycle && has_subscription_ended? && eligible_for_trial? && in_app_purchase.nil?
          GitHub.logger.info("Resuming cancelled trial for user",
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "subscribe",
            "gh.user.id" => user_object.id,
            "gh.copilot.can_resume_trial" => true
          )
          ::Billing::Public::SubscriptionItem.reactivate(
            product: copilot_pro_product,
            account: user_object,
            actor: user_object,
            free_trial_length: free_trial_length,
          )
        elsif active_subscription_is_pro_plus || active_subscription_is_max
          # In-app purchases require data to be stored within subscription_items extension tables: apple_subscriptions
          # and google_subscriptions. Currently, scheduling pending changes does not support temporarily storing
          # the data required for these extension tables. Therefore, we cannot schedule a downgrade.
          # This is currently OK as Apple _is_ our source-of-truth for in-app purchases and our daily job will
          # downgrade user subscriptions appropriately (but not using this method).
          if in_app_purchase
            return GitHub::Result.error(SignupError.new("In-app purchase items cannot currently be downgraded via scheduling."))
          end

          if active_subscription_is_max
            GitHub.dogstats.increment("copilot.subscription.downgrade_max_to_pro")
          end

          # This schedules a downgrade from Copilot Pro Plus or Copilot Max to Copilot Pro
          ::Billing::Public::SubscriptionItem.update(
            product: copilot_pro_product,
            account: user_object,
            actor: user_object,
          )
        elsif active_subscription_is_edu
          # upgrade from edu
          if FeatureFlag.vexi.enabled?(:billing_copilot_upgrade_orchestration, user_object, default: false)
            overage_cents = fetch_current_overage_cents(product_key: T.must(copilot_active_subscription_item).product_identifier.product_key.to_s, user_object: user_object)
            return GitHub::Result.error(SignupError.new("Something went wrong. Please try again.")) if overage_cents.nil?
          end
          ::Billing::Public::SubscriptionItem.update(
              product: copilot_pro_product,
              account: user_object,
              actor: user_object,
              quantity: 1,
              end_free_trial: true,
              in_app_purchase:
            )
        else
          ::Billing::Public::SubscriptionItem.create(
            product: copilot_pro_product,
            account: user_object,
            actor: user_object,
            free_trial_length: free_trial_length,
            in_app_purchase: in_app_purchase,
            perform_authorization: free_trial_length > 0 && user_object.feature_flag_enabled_or_raise?(:copilot_auth_before_signup), # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            authorization_amount_in_cents: ::Billing::Abuse::Copilot::AuthAndCapture::COPILOT_INDIVIDUAL_MONTHLY_RATE_IN_CENTS
          )
        end

        if result.ok?
          if user_object.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false)
            client = Copilot::Cache::SubscriptionAttemptedAtClient.new(user: user_object)
            client.store(Time.current.in_time_zone("UTC").to_i)
          end

          old_plan_key = if active_subscription_is_pro_plus
            Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY
          elsif active_subscription_is_max
            Copilot::INDIVIDUAL_MAX_PRODUCT_KEY
          elsif active_subscription_is_edu
            Copilot::EDU_PRODUCT_KEY
          end

          Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
            Copilot::Public::User.for(user_object),
            old_plan: old_plan_key ? Hydro::EntitySerializer.copilot_individual_plan(old_plan_key) : :UNKNOWN,
            new_plan: Hydro::EntitySerializer.copilot_individual_plan(Copilot::INDIVIDUAL_PRO_PRODUCT_KEY),
          )

          # Only the edu -> pro path is an upgrade; downgrades from Pro Plus/Max do not emit an upgrade event.
          if active_subscription_is_edu
            emit_plan_upgrade_event(
              overage_cents: overage_cents,
              old_product_key: old_plan_key,
              new_product_key: T.must(copilot_pro_product.product_key),
              payment_processor_transaction_id: result.value!.payment_id
            )
          end

          Copilot::FreeUser.find_by(user_id: user_object.id)&.cancel!

          copilot_user_object.invalidate_quota_cache!
        end

        unless result.ok?
          # there was an error, let's log it and all that good stuff
          exception_logging_context = {
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "subscribe",
            "gh.user.id" => user_object.id,
            "gh.billing.subscription_item.duration" => duration_billing_cycle,
            "gh.billing.subscription_item.free_trial_length" => free_trial_length,
          }

          GitHub.logger.error(result.error, exception_logging_context)
          GitHub.dogstats.increment("copilot.subscription.error")
        end

        if result.ok? && result.value!.on_free_trial?
          ::Billing::SendEmailToEloquaJob.perform_later(uri: FREE_TRIAL_ELOQUA_URI, email: user_object.email)
        end

        result
      end

      sig { params(duration: Symbol, in_app_purchase: T.nilable(::Billing::Public::InAppPurchase)).returns(GitHub::Result) }
      def subscribe_pro_plus(duration, in_app_purchase: nil)
        upgraded_from_pro_to_pro_plus = false
        old_plan_key = T.let(nil, T.nilable(String))
        duration_billing_cycle = if duration == :month
          ::Billing::Public::SubscriptionItems::BillingCycle::Month
        else
          ::Billing::Public::SubscriptionItems::BillingCycle::Year
        end

        if in_app_purchase && copilot_user_object.cfi_paid_plan_upgrade_restricted? && user_object.feature_flag_enabled?(:copilot_iap_cfi_signups_restricted, default: false)
          return GitHub::Result.error(SignupError.new("This plan for GitHub Copilot is currently not available"))
        end

        # For now we have no intention of selling anything other than monthly IAP CfI subscriptions.
        if duration_billing_cycle != ::Billing::Public::SubscriptionItems::BillingCycle::Month && in_app_purchase
          return GitHub::Result.error(SignupError.new("Only monthly plans are currently supported for in-app purchasing."))
        end

        copilot_pro_plus_product = copilot_pro_plus_product_identifier(duration: duration_billing_cycle)
        copilot_pro_product = copilot_pro_product_identifier(duration: duration_billing_cycle)

        # Fetch overage before the update so we can fail early
        overage_cents = nil
        is_downgrade = active_subscription_is_max
        # If `copilot_active_subscription_item` exists, it could be a Copilot Pro, Copilot Pro Plus, Copilot Max subscription item
        result = if copilot_active_subscription_item.present?
          active_product_identifier = T.must(copilot_active_subscription_item).product_identifier
          if FeatureFlag.vexi.enabled?(:billing_copilot_upgrade_orchestration, user_object, default: false)
            overage_cents = fetch_current_overage_cents(product_key: active_product_identifier.product_key.to_s, user_object: user_object)
            return GitHub::Result.error(SignupError.new("Something went wrong. Please try again.")) if overage_cents.nil?
          end
          if active_product_identifier == copilot_pro_plus_product
            GitHub::Result.error(SignupError.new("This Copilot Pro Plus subscription already exists"))
          elsif is_downgrade
            # Downgrade logic
            # In-app purchases require data to be stored within subscription_items extension tables: apple_subscriptions
            # and google_subscriptions. Currently, scheduling pending changes does not support temporarily storing
            # the data required for these extension tables. Therefore, we cannot schedule a downgrade.
            # This is currently OK as Apple _is_ our source-of-truth for in-app purchases and our daily job will
            # downgrade user subscriptions appropriately (but not using this method).
            if in_app_purchase
              return GitHub::Result.error(SignupError.new("In-app purchase items cannot currently be downgraded via scheduling."))
            end
            GitHub.dogstats.increment("copilot.subscription.downgrade_max_to_pro_plus")
            # This schedules a downgrade from Copilot Max to Copilot Pro Plus
            ::Billing::Public::SubscriptionItem.update(
              product: copilot_pro_plus_product,
              account: user_object,
              actor: user_object,
            )
          else
            # Upgrade logic
            if active_product_identifier == copilot_pro_product
              upgraded_from_pro_to_pro_plus = true
            end
            ::Billing::Public::SubscriptionItem.update(
              product: copilot_pro_plus_product,
              account: user_object,
              actor: user_object,
              quantity: 1,
              end_free_trial: true,
              in_app_purchase:
            )
          end
        else
          # First time subscribe logic
          ::Billing::Public::SubscriptionItem.create(
            product: copilot_pro_plus_product,
            account: user_object,
            actor: user_object,
            in_app_purchase:
          )
        end

        if result.ok?
          if user_object.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false)
            client = Copilot::Cache::SubscriptionAttemptedAtClient.new(user: user_object)
            client.store(Time.current.in_time_zone("UTC").to_i)
          end

          old_plan_key = if is_downgrade
            Copilot::INDIVIDUAL_MAX_PRODUCT_KEY
          elsif copilot_active_subscription_item.present?
            T.must(copilot_active_subscription_item).product_identifier.product_key
          end

          Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
            Copilot::Public::User.for(user_object),
            reset_quota: upgraded_from_pro_to_pro_plus && !user_object.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false),
            old_plan: old_plan_key ? Hydro::EntitySerializer.copilot_individual_plan(old_plan_key) : :UNKNOWN,
            new_plan: Hydro::EntitySerializer.copilot_individual_plan(Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY),
          )

          unless is_downgrade
            emit_plan_upgrade_event(
              overage_cents: overage_cents,
              old_product_key: old_plan_key,
              new_product_key: T.must(copilot_pro_plus_product.product_key),
              payment_processor_transaction_id: result.value!.payment_id
            )
          end
        end

        unless result.ok?
          exception_logging_context = {
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "subscribe_pro_plus",
            "gh.user.id" => user_object.id,
            "gh.billing.subscription_item.duration" => duration_billing_cycle,
          }

          GitHub.logger.error(result.error, exception_logging_context)
          GitHub.dogstats.increment("copilot_pro_plus.subscription.error")
        end

        result
      end

      sig { params(duration: Symbol, in_app_purchase: T.nilable(::Billing::Public::InAppPurchase)).returns(GitHub::Result) }
      def subscribe_max(duration, in_app_purchase: nil)
        unless user_object.feature_flag_enabled?(:copilot_max_sku_signup, default: false) || user_object.feature_flag_enabled?(:copilot_iap_max_sku, default: false)
          return GitHub::Result.error(SignupError.new("Copilot Max is not yet available."))
        end

        unless meets_trust_tier_requirements_for_max?
          return GitHub::Result.error(SignupError.new("Copilot Max isn't available for your account yet. Access is currently limited while we expand our rollout."))
        end

        duration_billing_cycle = if duration == :month
          ::Billing::Public::SubscriptionItems::BillingCycle::Month
        else
          ::Billing::Public::SubscriptionItems::BillingCycle::Year
        end

        # For now we have no intention of selling anything other than monthly IAP CfI subscriptions.
        if duration_billing_cycle != ::Billing::Public::SubscriptionItems::BillingCycle::Month && in_app_purchase
          return GitHub::Result.error(SignupError.new("Only monthly plans are currently supported for in-app purchasing."))
        end

        copilot_max_product = copilot_max_product_identifier(duration: duration_billing_cycle)

        old_plan_key = T.let(nil, T.nilable(String))

        # Fetch overage before the update so we can fail early
        overage_cents = nil
        result = if copilot_active_subscription_item.present?
          active_product_identifier = T.must(copilot_active_subscription_item).product_identifier
          if FeatureFlag.vexi.enabled?(:billing_copilot_upgrade_orchestration, user_object, default: false)
            overage_cents = fetch_current_overage_cents(product_key: active_product_identifier.product_key.to_s, user_object: user_object)
            return GitHub::Result.error(SignupError.new("Something went wrong. Please try again.")) if overage_cents.nil?
          end
          if active_product_identifier == copilot_max_product
            GitHub::Result.error(SignupError.new("This Copilot Max subscription already exists"))
          else
            old_plan_key = T.must(active_product_identifier.product_key)
            update_result = ::Billing::Public::SubscriptionItem.update(
              product: copilot_max_product,
              account: user_object,
              actor: user_object,
              quantity: 1,
              end_free_trial: true,
              in_app_purchase:
            )
            GitHub.dogstats.increment("copilot_max.subscription.updated", tags: ["from:#{T.must(copilot_active_subscription_item).name}"])
            update_result
          end
        else
          unless copilot_max_new_signup_enabled?
            return GitHub::Result.error(SignupError.new("Copilot Max is only available as an upgrade from an existing paid plan."))
          end

          create_result = ::Billing::Public::SubscriptionItem.create(
            product: copilot_max_product,
            account: user_object,
            actor: user_object,
            in_app_purchase:
          )
          GitHub.dogstats.increment("copilot_max.subscription.created")
          create_result
        end

        if result.ok?
          Copilot::LimitedUser.find_by(user_id: user_object.id)&.destroy
          Copilot::FreeUser.find_by(user_id: user_object.id)&.cancel!
          if user_object.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false)
            client = Copilot::Cache::SubscriptionAttemptedAtClient.new(user: user_object)
            client.store(Time.current.in_time_zone("UTC").to_i)
          end
          Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
            Copilot::Public::User.for(user_object),
            reset_quota: !user_object.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false),
            old_plan: old_plan_key ? Hydro::EntitySerializer.copilot_individual_plan(old_plan_key) : :UNKNOWN,
            new_plan: Hydro::EntitySerializer.copilot_individual_plan(Copilot::INDIVIDUAL_MAX_PRODUCT_KEY),
          )
          emit_plan_upgrade_event(
            overage_cents: overage_cents,
            old_product_key: old_plan_key,
            new_product_key: T.must(copilot_max_product.product_key),
            payment_processor_transaction_id: result.value!.payment_id
          )
        end

        unless result.ok?
          exception_logging_context = {
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "subscribe_max",
            "gh.user.id" => user_object.id,
            "gh.billing.subscription_item.duration" => duration_billing_cycle,
          }

          GitHub.logger.error(result.error, exception_logging_context)
          GitHub.dogstats.increment("copilot_max.subscription.error")
        end

        result
      end

      sig { returns(GitHub::Result) }
      def subscribe_educational
        GitHub.logger.with_named_tags({
          "gh.user.id" => user_object.id
        }) do
          coupon_redemption = user_object.coupon_redemption

          unless has_student_coupon?
            GitHub.dogstats.increment("copilot_edu_sku.signup.no_student_coupon")
            return GitHub::Result.error(SignupError.new("User does not have a valid student coupon"))
          end

          # They have a student coupon but it's expired
          if coupon_redemption&.expired?

            # they still have an active EDU SKU SubscriptionItem we haven't deactivated
            # This is very unlikely since we listen to coupon expiration
            active_edu_sku = active_subscription_is_edu
            if active_edu_sku
              GitHub.logger.info("Coupon has expired and active EDU SKU subscription item exists, cancelling",
                                { "gh.subscription_item.id": copilot_active_subscription_item&.id })

              cancel_active_edu_subscription
            end

            GitHub.dogstats.increment("copilot_edu_sku.signup.student_coupon_expired", tags: ["sku_active:#{active_edu_sku}"])
            return GitHub::Result.error(SignupError.new("Student coupon has expired."))
          end

          # if active subscription item is not a copilot subscription item
          if !copilot_active_subscription_item
            # Check for cancelled educational subscription items to reactivate
            cancelled_edu_subscription_items = all_copilot_subscription_items.map do |item|
              product_identifier = ::Billing::Public::SubscriptionItem.new(item).product_identifier
              [item, product_identifier]
            end.select do |item, product_identifier|
              product_identifier.same?(copilot_edu_product_identifier, match_billing_cycle: false) && item.cancelled?
            end

            if cancelled_edu_subscription_items.any?
              return reactivate_educational_subscription_item
            else
              return create_educational_subscription_item(T.must(coupon_redemption))
            end
          end

          # doing this for sorbet
          active_subscription_item = T.must(copilot_active_subscription_item)

          # user has an active copilot subscription item that isn't educational, AKA they're paying us
          # if we decide to allow people to downgrade, we'll need to figure out a way around the fact that cancelling and refunding is async
          if !active_subscription_is_edu
            active_product_key = active_subscription_item.product_identifier.product_key
            GitHub.dogstats.increment("copilot_edu_sku.signup.already_subscribed_to_paid_sku",
                                      tags: ["sku:#{active_product_key}"])
            GitHub.logger.info("User is already subscribed to a paid SKU",
                               { "gh.subscription_item.id" => active_subscription_item.id,  })
            return GitHub::Result.error(SignupError.new("User is already subscribed to a paid SKU"))
          end

          # if we made it here they already have a valid coupon and active subscription item.
          return GitHub::Result.new do
            GitHub.logger.info("User already has an active educational subscription item",
                               { "gh.subscription_item.id" => active_subscription_item.id })
            GitHub.dogstats.increment("copilot_edu_sku.signup.has_active_edu_subscription")
            copilot_active_subscription_item
          end
        end
      end

      sig { returns(GitHub::Result) }
      def reactivate_educational_subscription_item
        GitHub.logger.info("Reactivating cancelled educational subscription item")
        result = ::Billing::Public::SubscriptionItem.reactivate(
          product: copilot_edu_product_identifier,
          account: user_object,
          actor: user_object
        )
        GitHub.dogstats.increment("copilot_edu_sku.signup.reactivated")
        Copilot::Instrumenter.instrument_student_reactivated(copilot_user_object)
        if result.ok?
          Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
            Copilot::Public::User.for(user_object),
            reset_quota: true,
            new_plan: Hydro::EntitySerializer.copilot_individual_plan(Copilot::EDU_PRODUCT_KEY),
          )
        end
        result
      end

      sig { params(coupon_redemption: ::CouponRedemption).returns(GitHub::Result) }
      def create_educational_subscription_item(coupon_redemption)
        coupon_code = coupon_redemption.coupon&.code
        GitHub.logger.info("Creating new educational subscription item", { "gh.coupon_redemption.id" => coupon_redemption.id,
                           "gh.coupon_code" => coupon_code })
        result = ::Billing::Public::SubscriptionItem.create(
          product: copilot_edu_product_identifier,
          account: user_object,
          actor: user_object
        )
        GitHub.dogstats.increment("copilot_edu_sku.signup.created", tags: ["coupon_code:#{coupon_code}"])
        Copilot::Instrumenter.instrument_student_subscribed(copilot_user_object)
        if result.ok?
          Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
            Copilot::Public::User.for(user_object),
            reset_quota: true,
            new_plan: Hydro::EntitySerializer.copilot_individual_plan(Copilot::EDU_PRODUCT_KEY),
          )
        end
        result
      end

      # For CfB users, this is when the earliest Copilot::Seat was created
      # For CfI free users, this is when their Copilot::FreeUser record was created
      # For CfI FREE PLAN users, this is when their Copilot::LimitedUser record was created
      # For CfI paid users, this is when their copilot_active_subscription_item was created
      # For all other cases, return nil
      sig { returns(T.nilable(String)) }
      def assigned_date
        if has_cfb_access?
          # Pick the earliest associated Copilot::Seat for now
          Copilot::Seat.for_user(user_object).order(created_at: :asc).first&.created_at&.iso8601
        elsif has_free_access?
          T.must(free_user).created_at&.iso8601
        elsif has_limited_access?
          T.must(limited_user).subscribed_at&.iso8601
        elsif has_cfi_access? && has_active_subscription?
          async_copilot_active_subscription_item.sync&.created_at&.iso8601
        elsif has_limited_access?
          T.must(limited_user).created_at&.iso8601
        else
          nil
        end
      end

      sig { returns(GitHub::Result) }
      def upgrade_trial
        GitHub.logger.info("Upgrading CfI trial if it exists")

        ::Billing::Public::SubscriptionItem.end_free_trial_now!(
          actor: user_object,
          product: copilot_pro_product_identifier,
          account: user_object,
          purchase_subscription: true,
          seats: 1
        )
      end

      sig { params(organization: T.nilable(::Organization)).returns(GitHub::Result) }
      def cancel_and_refund_active_subscription(organization: nil)
        GitHub.logger.info("Canceling CfI subscription if it exists")

        unless copilot_active_subscription_item.present?
          GitHub.logger.info("Subscription Item Does Not Exist")
          return GitHub::Result.new do
            false
          end
        end

        GitHub::Result.new do
          GitHub.logger.info("Subscription Item Does Exist")
          # capture before cancellation since the item may be cleared from cache afterwards
          was_edu_subscription = active_subscription_is_edu

          # let's see if they have a seat (they must)
          seat = Copilot::Seat.where(
            organization: organization,
            assigned_user: user_object
          ).first

          if seat.nil?
            ############ 🚨🚨🚨🚨 THIS SHOULDN'T HAPPEN 🚨🚨🚨🚨 ############
            # if they don't have a seat, we can't cancel their subscription
            # we shouldn't have this method called without a seat, but evidently....
            msg = "No seat found for cancel and refund"
            err = StandardError.new(msg)
            Failbot.report(
              err,
              user: user_object,
              organization: organization,
            )
            GitHub.logger.info(msg)
            Kernel.raise(err)
          end

          GitHub.logger.info("Cancelling and refunding")
          result = ::Billing::Public::SubscriptionItem.cancel_and_refund(
            product: T.must(copilot_active_subscription_item).product_identifier,
            account: user_object,
            organization: organization,
            allow_cancelling_iap: true
          )

          if result.ok?
            Copilot::Instrumenter.instrument_copilot_for_business_individual_seat_converted(
              user_object,
              T.must(copilot_active_subscription_item),
              seat,
            )

            if was_edu_subscription
              Copilot::Instrumenter.instrument_student_cancelled(copilot_user_object)
            end

            ::Billing::SendEmailToEloquaJob.perform_later(uri: CANCEL_TRIAL_ELOQUA_URI, email: user_object.email)

            result.value!
          else
            GitHub.logger.info("Subscription exists, but could not be cancelled")
            false
          end
        end
      end

      sig { params(reason: Symbol).returns(GitHub::Result) }
      def cancel_active_edu_subscription(reason: :expired)
        unless copilot_active_subscription_item.present? && active_subscription_is_edu
          GitHub.logger.info("Educational Subscription Item Does Not Exist")
          return GitHub::Result.new do
            false
          end
        end

        GitHub::Result.new do
          GitHub.logger.info("Educational Subscription Item Does Exist")
          result = ::Billing::Public::SubscriptionItem.cancel(
            product: copilot_edu_product_identifier, account: user_object, actor: user_object,
          )

          if result.ok?
            GitHub.logger.info("Educational subscription cancelled")
            GitHub.dogstats.increment("copilot.educational_subscription.cancelled")
            if reason == :cancelled
              Copilot::Instrumenter.instrument_student_cancelled(copilot_user_object)
            else
              Copilot::Instrumenter.instrument_student_expired(copilot_user_object)
            end
            result.value!
          else
            GitHub.logger.info("Educational subscription exists, but could not be cancelled")
            false
          end
        end
      end

      # This will return either a Copilot Pro, Pro Plus, Max, or Edu subscription item
      sig { override.returns(T.nilable(::Billing::Public::SubscriptionItem)) }
      def copilot_active_subscription_item
        @copilot_active_subscription_item ||= T.let(
          ::Billing::Public::SubscriptionItem
          .all_active(
            product: copilot_product_type_identifier,
            account: user_object
          )
          .value { [] }
          .first,
          T.nilable(::Billing::Public::SubscriptionItem),
        )
      end

      sig { returns(T::Boolean) }
      def active_subscription_is_max
        !!(copilot_active_subscription_item && copilot_max_product_identifier.same?(T.must(copilot_active_subscription_item).product_identifier, match_billing_cycle: false))
      end

      sig { returns(T::Boolean) }
      def active_subscription_is_edu
        !!(copilot_active_subscription_item && copilot_edu_product_identifier.same?(T.must(copilot_active_subscription_item).product_identifier, match_billing_cycle: false))
      end

      sig { returns(T::Boolean) }
      def any_edu_subscription_items?
        all_copilot_subscription_items.any? do |item|
          product_identifier = ::Billing::Public::SubscriptionItem.new(item).product_identifier
          copilot_edu_product_identifier.same?(product_identifier, match_billing_cycle: false)
        end
      end

      sig { override.returns(Promise[T.untyped]) } # rubocop:todo Sorbet/ForbidTUntyped
      def async_copilot_active_subscription_item
        Platform::Loaders::ActiveRecord.load(::User, user_object.id).then do |user|
          uuid_relation = ::Billing::ProductUUID.where(product_type: Copilot::PRODUCT_TYPE, product_key: Copilot::INDIVIDUAL_PRODUCT_KEYS)

          Platform::Loaders::ActiveRecord.load_relation(uuid_relation).then do |uuids|
            subscribable_ids = uuids.map(&:id)
            T.must(user).async_plan_subscription.then do |plan_subscription|
              next unless plan_subscription.present?

              relation = plan_subscription.active_subscription_items.where(
                subscribable_type: "Billing::ProductUUID",
                subscribable_id: subscribable_ids,
              )

              Platform::Loaders::ActiveRecord.load_relation(relation).then do |subscription_items|
                Promise.resolve(subscription_items.first)
              end
            end
          end
        end
      end

      sig { override.returns(Integer) }
      def days_left_on_trial
        # gotta have a subscription item to have a trial
        return -1 unless copilot_active_subscription_item.present?

        item = T.must(copilot_active_subscription_item)

        # gotta have a free trial to have days left on trial
        return -1 unless item.free_trial_ends_on.present?

        (item.free_trial_ends_on.to_date - Date.current).to_i
      end

      sig { override.returns(Integer) }
      def days_until_next_billing_date
        # gotta have a subscription item to have a billing date
        return -1 unless copilot_active_subscription_item.present?

        item = T.must(copilot_active_subscription_item)

        # gotta have a billing date to have days until next billing date
        return -1 unless item.next_billing_date.present?

        (Date.current - item.next_billing_date.to_date).to_i
      end

      sig { returns(T.nilable(Copilot::FreeUser)) }
      def free_user
        @free_user ||= T.let(
          Copilot::FreeUser.find_for_copilot_user(copilot_user_object),
          T.nilable(Copilot::FreeUser),
        )
      end

      sig { override.returns(T.nilable(Copilot::LimitedUser)) }
      def limited_user
        @limited_user ||= T.let(
          Copilot::LimitedUser.for_subscribed_user(user_object),
          T.nilable(Copilot::LimitedUser),
        )
      end

      sig { params(duration: T.nilable(::Billing::Public::SubscriptionItems::BillingCycle)).returns(::Billing::Public::Product::ProductIdentifier) }
      def copilot_product_type_identifier(duration: nil)
        ::Billing::Public::Product::ProductIdentifier.new(
          product_type: Copilot::PRODUCT_TYPE,
          billing_cycle: duration,
        )
      end

      sig { params(duration: T.nilable(::Billing::Public::SubscriptionItems::BillingCycle)).returns(::Billing::Public::Product::ProductIdentifier) }
      def copilot_pro_product_identifier(duration: nil)
        ::Billing::Public::Product::ProductIdentifier.new(
          product_type: Copilot::PRODUCT_TYPE,
          product_key: Copilot::INDIVIDUAL_PRO_PRODUCT_KEY,
          billing_cycle: duration,
        )
      end

      sig { params(duration: T.nilable(::Billing::Public::SubscriptionItems::BillingCycle)).returns(::Billing::Public::Product::ProductIdentifier) }
      def copilot_pro_plus_product_identifier(duration: nil)
        ::Billing::Public::Product::ProductIdentifier.new(
          product_type: Copilot::PRODUCT_TYPE,
          product_key: Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY,
          billing_cycle: duration,
        )
      end

      sig { params(duration: T.nilable(::Billing::Public::SubscriptionItems::BillingCycle)).returns(::Billing::Public::Product::ProductIdentifier) }
      def copilot_max_product_identifier(duration: nil)
        ::Billing::Public::Product::ProductIdentifier.new(
          product_type: Copilot::PRODUCT_TYPE,
          product_key: Copilot::INDIVIDUAL_MAX_PRODUCT_KEY,
          billing_cycle: duration,
        )
      end

      sig { returns(T::Array[::Billing::SubscriptionItem]) }
      def non_edu_copilot_subscription_items
        all_copilot_subscription_items.reject do |item|
          product_identifier = ::Billing::Public::SubscriptionItem.new(item).product_identifier
          copilot_edu_product_identifier.same?(product_identifier, match_billing_cycle: false)
        end
      end

      sig { returns(::Billing::Public::Product::ProductIdentifier) }
      def copilot_edu_product_identifier
        ::Billing::Public::Product::ProductIdentifier.new(
          product_type: Copilot::PRODUCT_TYPE,
          product_key: Copilot::EDU_PRODUCT_KEY,
          billing_cycle: ::Billing::Public::SubscriptionItems::BillingCycle::Month, #EDU is always monthly
        )
      end

      sig { override.returns(T::Boolean) }
      memoize def use_token_based_billing?
        return false if user_object.feature_flag_enabled?(:copilot_skip_token_based_billing_check_dotcom, default: false) # just in case something is going terribly wrong with calculate method
        result, err_msg = calculate_use_token_based_billing
        # strip out anything in () since we use that for dynamic tags and we don't want that cardinality in our metrics
        if err_msg.present? && err_msg != "copilot_token_based_billing flag not enabled"
          GitHub.dogstats.increment("copilot.user.use_token_based_billing.false", tags: ["reason:#{err_msg.gsub(/\s*\([^)]*\)/, "")}"])
        end
        result
      end

      sig { returns(T::Boolean) }
      memoize def cfi_intervals_enabled?
        user_object.feature_flag_enabled?(:cfi_intervals_enabled, default: false)
      end

      sig { returns([T::Boolean, T.nilable(String)]) }
      memoize def calculate_use_token_based_billing
        Copilot::TokenBasedBilling.enabled?(
          billable_owner: billable_owner_for_tbb,
        )
      end

      ## If CE/CB is enabled, we want to use the billable owner for TBB, otherwise we want to use the user object
      sig { returns(T.nilable(T.any(Copilot::User, Copilot::Organization, Copilot::Business))) }
      memoize def billable_owner_for_tbb
        return copilot_user_object unless has_cfb_access? || has_cfe_access?
        #TODO set up scientist experiment to see if you can use this in load_consumptive_user_response
        if has_multi_access?
          owner = T.let(nil, T.nilable(T.any(Copilot::Organization, Copilot::Business)))
          Copilot::Seat.for_user(user_object).each do |seat|
            next unless seat.seat_assignment.present?
            next unless seat.seat_assignment.owner.present?
            next unless seat.customer_id == copilot_user_object.billable_customer_id

            seat_owner = seat.seat_assignment.owner

            if seat_owner.is_a?(::Business)
              owner = Copilot::Business.new(seat_owner)
            elsif seat_owner.is_a?(::Organization)
              if seat_owner.business.present?
                owner = Copilot::Business.new(T.must(seat_owner.business))
              else
                owner = Copilot::Organization.new(seat_owner)
              end
            else
              # Not an expected owner type, so continue
              next
            end

            break
          end
          owner
        else
          cp = copilot_provider
          case cp
          when Copilot::Organization
            return cp unless cp.business.present?
            return Copilot::Business.new(T.must(cp.business))
          end
          cp
        end
      end

      sig { returns(T.nilable(Date)) }
      memoize def copilot_pro_trial_start_date
        subscription_item = ::Billing::SubscriptionItem.find(copilot_active_subscription_item&.id)
        return nil unless subscription_item.present? && subscription_item.free_trial_ends_on.present?
        return nil unless T.must(copilot_active_subscription_item).product_identifier.product_key == INDIVIDUAL_PRO_PRODUCT_KEY

        subscription_item.free_trial_ends_on - Copilot.free_trial_length.days
      end

      # Fetches current overage cents from billing platform.
      # Returns overage_cents on success, or nil if the fetch fails.
      sig { params(product_key: String, user_object: ::User).returns(T.nilable(Integer)) }
      def fetch_current_overage_cents(product_key:, user_object:)
        copilot_plan = Copilot::CfiPlanResolver::PRODUCT_KEY_TO_COPILOT_PLAN[product_key]
        return nil unless copilot_plan

        customer = user_object.customer
        return nil unless customer

        trust_tier = TrustTiers::Tier.for_billable_owner(user_object).tier
        entity_detail = BillingPlatform::Base::EntityDetail.new(
          customerId: customer.id.to_s,
          copilotPlan: copilot_plan,
        )

        now = Time.now.utc
        response = ::Billing::Platform::Api::Client.new.get_spending_info(
          customer_id: customer.id,
          product: "copilot",
          entity_detail: entity_detail,
          trust_tier: trust_tier,
          year: now.year,
          month: now.month,
        )

        if response.is_a?(::Billing::Platform::Api::Error)
          Failbot.report(response,
            "gh.billing.customer.id" => customer.id,
            "gh.billing.trust_tier" => trust_tier,
            "gh.copilot.product_key" => product_key,
            "gh.copilot.plan" => copilot_plan,
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "fetch_current_overage_cents",
          )
          return nil
        end

        return nil if response[:status] == :SPENDING_STATUS_NOT_APPLICABLE

        # Fall back to the per-plan amount when totalOverageAmount is absent (older gem or test stub).
        overage_amount = if FeatureFlag.vexi.enabled?(:billing_copilot_upgrade_total_overage, user_object, default: false)
          response[:totalOverageAmount] || response[:overageAmount]
        else
          response[:overageAmount]
        end
        return nil unless overage_amount.is_a?(Numeric)

        (Kernel.BigDecimal(overage_amount.to_s) * 100).ceil.to_i
      end

      sig do
        params(
          overage_cents: T.nilable(Integer),
          old_product_key: T.nilable(String),
          new_product_key: String,
          payment_processor_transaction_id: T.nilable(String),
        ).void
      end
      def emit_plan_upgrade_event(overage_cents:, old_product_key:, new_product_key:, payment_processor_transaction_id:)
        return unless overage_cents && old_product_key && payment_processor_transaction_id
        return unless FeatureFlag.vexi.enabled?(:billing_copilot_upgrade_orchestration, user_object, default: false)

        emitter = Copilot::Billing::PaymentEventEmitter.new(copilot_user_object)
        emitter.emit_plan_upgrade(old_product_key: old_product_key, new_product_key: new_product_key, payment_processor_transaction_id: payment_processor_transaction_id, current_overage_cents: overage_cents)
      end
    end
  end
end
