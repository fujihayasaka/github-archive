# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module Subscription
      extend T::Helpers
      include Copilot::Users::Signatures

      abstract!

      include Copilot::Errors

      ## Signup related functionality
      PRODUCT_TYPE = "github.copilot"
      PRODUCT_KEY = "v0"

      FREE_TRIAL_ELOQUA_URI = "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1654873045572&elqSiteID=88570519"
      CANCEL_TRIAL_ELOQUA_URI = "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1660759955375&elqSiteId=88570519"

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
        !has_cfi_access? && !has_cfb_access? && !can_signup_for_free?
      end

      # A user can signup for free as long as they
      # 1. do not have an active billing subscription (including trial) and
      # 2. they have a free_user record that is not subscribed
      #
      # @return [Boolean] whether they can sign up for free
      sig { override.returns(T::Boolean) }
      def can_signup_for_free?
        return false if has_active_subscription? || has_trial_subscription?
        return false unless free_user.present?

        !T.must(free_user).subscribed?
      end

      # A user can signup for limited as long as they
      # 1. do not have an active billing subscription (including trial) and
      # 2. they have a free_user record that is not subscribed
      #
      # @return [Boolean] whether they can sign up for free
      sig { override.returns(T::Boolean) }
      def can_signup_for_limited?
        return false if has_signed_up?
        return false unless limited_user.present?

        !T.must(limited_user).subscribed?
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
          item.subscribable.is_a?(::Billing::ProductUUID) && item.subscribable.product_type == PRODUCT_TYPE
        end.to_a
      end

      # Checks if there ever was a paid copilot subscription
      sig { override.returns(T::Boolean) }
      def trial_only_subscription?
        all_copilot_subscription_items.any? && all_copilot_subscription_items.none?(&:latest_billing_transaction)
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
        return false if has_active_subscription? || has_trial_subscription? || is_technical_preview_user?

        return true if eligible_for_cancelled_trial_resumption?

        ::Billing::Public::SubscriptionItem.eligible_for_free_trial?(
          product: product_identifier,
          account: user_object,
        )
      end

      sig { returns(T::Boolean) }
      def eligible_for_cancelled_trial_resumption?
        if trial_only_subscription? && user_object.feature_enabled?(:copilot_allow_trial_resumption)
          trialed_seconds = all_copilot_subscription_items.map do |i|
            next unless i.free_trial_ends_on

            # If the free trial ends on date is in the future but the trial is cancelled, something's gone wrong
            # with the cancellation process and we should allow the user to resume their trial
            return true if i.free_trial_ends_on > Time.now

            # when we cancel a trial, we set trial_ends_at to 1.day.ago, so it can be before `created_at`
            [i.free_trial_ends_on.to_time - i.created_at, 0].max.to_i
          end.compact.sum.seconds

          GitHub.logger.info("User's trial resumption eligibility was checked",
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "eligible_for_cancelled_trial_resumption?",
            "gh.user.id" => user_object.id,
            "gh.copilot.trialed_seconds" => trialed_seconds,
            "gh.copilot.can_resume_trial" => trialed_seconds < 1.day
          )

          return true if trialed_seconds < 1.day
        end

        false
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
      sig { override.returns(GitHub::Result) }
      def subscribe_limited_user
        GitHub::Result.new do
          GitHub.logger.with_named_tags(
            "gh.user.id" => user_object.id,
            "gh.spammy" => spammy?,
            "gh.copilot.administrative_blocked" => administrative_blocked?,
            "gh.copilot.limited_user.present" => limited_user.present?,
            "gh.copilot.can_signup_for_limited" => can_signup_for_limited?,
          ) do
            # we need to make sure that the user isn't spammy or blocked
            if spammy? || administrative_blocked?
              GitHub.logger.info("User is spammy or blocked, not allowing signup")
              Kernel.raise SignupError.new("It appears you are not eligible to sign up to GitHub Copilot Limited")
            end

            # the user must also have a verified email
            if user_object.should_verify_email?
              GitHub.logger.info("User does not have a verified email, not allowing signup")
              Kernel.raise SignupError.new("It appears you are not eligible to sign up to GitHub Copilot Limited")
            end

            # the user must also not have a free or paid subscription
            unless limited_user.present? && can_signup_for_limited?
              GitHub.logger.info("User is not eligible to sign up for limited")
              Kernel.raise SignupError.new("It appears you are not eligible to sign up to GitHub Copilot Limited")
            end

            GitHub.logger.info("Subscribing user to limited")
            T.must(limited_user).subscribe
          end
        end
      end

      sig do
        override.params(
          duration: Symbol,
          in_app_purchase: T.nilable(::Billing::Public::InAppPurchase)
        ).returns(GitHub::Result)
      end
      def subscribe(duration, in_app_purchase: nil)
        if can_signup_for_free? && free_user
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

        # Do not use the new reactivation flow for IAP since it does not currently support it.
        result = if has_subscription_ended? && eligible_for_trial? && in_app_purchase.nil?
          GitHub.logger.info("Resuming cancelled trial for user",
            "code.namespace" => "Copilot::Users::Subscription",
            "code.function" => "subscribe",
            "gh.user.id" => user_object.id,
            "gh.copilot.can_resume_trial" => true
          )
          ::Billing::Public::SubscriptionItem.reactivate(
            product: product_identifier(duration: duration_billing_cycle),
            account: user_object,
            actor: user_object,
            free_trial_length: free_trial_length,
          )
        else
          ::Billing::Public::SubscriptionItem.create(
            product: product_identifier(duration: duration_billing_cycle),
            account: user_object,
            actor: user_object,
            free_trial_length: free_trial_length,
            in_app_purchase: in_app_purchase,
            perform_authorization: free_trial_length > 0 && user_object.feature_enabled?(:copilot_auth_before_signup),
            authorization_amount_in_cents: Copilot::AuthAndCapture::COPILOT_INDIVIDUAL_MONTHLY_RATE_IN_CENTS,
          )
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

      # For CfB users, this is when the earliest Copilot::Seat was created
      # For CfI free users, this is when their Copilot::FreeUser record was created
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
          product: product_identifier,
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

          product_query = {
            product_type: "github.copilot",
            product_key: "v0",
            billing_cycle: T.must(copilot_active_subscription_item).interval,
          }
          copilot_product = ::Billing::ProductUUID.find_sole_by(product_query)

          GitHub.logger.info("Cancelling and refunding")
          result = ::Billing::Public::SubscriptionItem.cancel_and_refund(
            product: copilot_product,
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

            ::Billing::SendEmailToEloquaJob.perform_later(uri: CANCEL_TRIAL_ELOQUA_URI, email: user_object.email)

            result.value!
          else
            GitHub.logger.info("Subscription exists, but could not be cancelled")
            false
          end
        end
      end

      sig { override.returns(T.nilable(::Billing::Public::SubscriptionItem)) }
      def copilot_active_subscription_item
        @copilot_active_subscription_item ||= T.let(
          ::Billing::Public::SubscriptionItem
          .all_active(
            product: product_identifier,
            account: user_object,
          )
          .value { [] }
          .first,
          T.nilable(::Billing::Public::SubscriptionItem),
        )
      end

      sig { override.returns(Promise[T.untyped]) } # rubocop:todo Sorbet/ForbidTUntyped
      def async_copilot_active_subscription_item
        Platform::Loaders::ActiveRecord.load(::User, user_object.id).then do |user|
          uuid_relation = ::Billing::ProductUUID.where(product_type: "github.copilot", product_key: "v0")

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
          Copilot::LimitedUser.find_for_copilot_user(copilot_user_object),
          T.nilable(Copilot::LimitedUser),
        )
      end

      sig { params(duration: T.nilable(::Billing::Public::SubscriptionItems::BillingCycle)).returns(::Billing::Public::Product::ProductIdentifier) }
      def product_identifier(duration: nil)
        ::Billing::Public::Product::ProductIdentifier.new(
          product_type: PRODUCT_TYPE,
          product_key: PRODUCT_KEY,
          billing_cycle: duration,
        )
      end
    end
  end
end
