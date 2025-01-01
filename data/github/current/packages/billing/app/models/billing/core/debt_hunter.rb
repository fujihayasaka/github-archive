# typed: strict
# frozen_string_literal: true

# Manages the daily Billing Run
module Billing
  module Core
    module DebtHunter
      BATCH_SIZE = 100
      MAX_THROTTLE_RETRIES = 4

      sig { params(block: T.proc.void).void }
      def self.read_from_replica(&block)
        ActiveRecord::Base.connected_to(role: :reading, &block)
      end

      sig { params(block: T.proc.void).void }
      def self.throttle_writes(&block)
        ApplicationRecord::Domain::Users.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, &block)
      rescue Freno::Throttler::Error => e
        GitHub.dogstats.increment("billing.run.throttle_with_retry.error", tags: ["retry:#{MAX_THROTTLE_RETRIES}"])
        raise e, "Exhausted throttler retries (#{MAX_THROTTLE_RETRIES} times)."
      end

      # Kick off the daily billing run. This grabs a list of users IDs that need
      # to be billed from MySQL and then processes a charge for each.
      #
      # This method (and its containing job, BillingRunStartJob)
      # assume that no external API calls are made in `run_charges`.
      #
      sig { void }
      def self.run_start
        read_from_replica do
          Business.needs_billed.find_in_batches(batch_size: BATCH_SIZE) do |businesses_in_batch|
            start_time = Time.now
            prefill_business_data_for_run_start(businesses_in_batch)
            businesses_in_batch.each do |business|
              process(business)
            end
            GitHub.dogstats.timing("billing.run.batch.time", GitHub::Dogstats.duration(start_time), tags: ["entity_type:business"])
          end
          User.needs_billed.find_in_batches(batch_size: BATCH_SIZE) do |users_in_batch|
            start_time = Time.now
            prefill_user_data_for_run_start(users_in_batch)
            users_in_batch.each do |user|
              process(user)
            end
            GitHub.dogstats.timing("billing.run.batch.time", GitHub::Dogstats.duration(start_time), tags: ["entity_type:user"])
          end
        end
      end

      # Public: Bulk-load relations on the given list of businesses to avoid n+1 queries.
      #
      # businesses - an Array or ActiveRecord::Relation of Business records
      #
      sig { params(businesses: T::Array[Business]).void }
      def self.prefill_business_data_for_run_start(businesses)
        GitHub::PrefillAssociations.prefill_associations(businesses, {
          customer: [:plan_subscription, :payment_method],
        })
      end

      # Public: Bulk-load relations on the given list of users to avoid n+1 queries.
      #
      # users - an Array or ActiveRecord::Relation of User and Organization records
      sig { params(users: T::Array[User]).void }
      def self.prefill_user_data_for_run_start(users)
        GitHub::PrefillAssociations.prefill_associations(users, :plan_subscription)

        plan_subs = users.map(&:plan_subscription).compact
        GitHub::PrefillAssociations.prefill_associations(plan_subs, :user, available_records: users)

        GitHub::PrefillAssociations.prefill_associations(users, { customer: :payment_method })
        GitHub::PrefillAssociations.prefill_batch_method(users, :coupon_redemption)

        enterprise_cloud_trials = users.map(&:enterprise_cloud_trial).compact
        GitHub::PrefillAssociations.prefill_batch_method(enterprise_cloud_trials, :active?)
      end

      # Performs the billing run for a single entity
      sig { params(billable_entity: ::Billing::Types::Account).void }
      def self.process(billable_entity)
        log_entity_information(billable_entity)

        if billable_entity.delegate_billing_to_business?
          action = "delegate_billing_to_business"
        elsif should_dun?(billable_entity)
          action = "dun_for_no_payment_method"
          dun_for_no_payment_method(billable_entity)
        elsif billable_entity.beneficiary?
          action = "disable_beneficiary"
          disable_beneficiary(billable_entity)
        elsif !billable_entity.external_subscription?
          action = "run_charges"
          run_charges(billable_entity)
        else
          action = "none"
        end

        GitHub.dogstats.increment("billing.run.processed", tags: ["action:#{action}", "entity_type:#{billable_entity.class.name}"])
      rescue StandardError => error # rubocop:todo Lint/GenericRescue
        Failbot.report(error, { "gh.user.id" => billable_entity.id })
        GitHub.dogstats.increment("billing.run.error", tags: ["error:#{error.class.name}"])
      end

      # Processes a charge for the entity
      sig { params(billable_entity: ::Billing::Types::Account).void }
      def self.run_charges(billable_entity)
        throttle_writes { billable_entity.recurring_charge }
      end

      # Disables users and businesses that are benefiting from falling outside
      # of the dunning cycle.
      sig { params(billable_entity: ::Billing::Types::Account).void }
      def self.disable_beneficiary(billable_entity)
        message =
          if billable_entity.is_a?(User) && billable_entity.coupon_expired_since_last_billing?
            "Your coupon was recently expired with no payment method on file."
          else
            "No payment method on file."
          end

        BillingNotificationsMailer.never_entered_dunning_failure(billable_entity, message).deliver_later
        throttle_writes { billable_entity.disable! }
      end

      # Should this user or business pay us but not be disabled yet (i.e. they
      # haven't exhausted their billing attempts)?
      sig { params(billable_entity: ::Billing::Types::Account).returns(T::Boolean) }
      def self.should_dun?(billable_entity)
        !billable_entity.has_valid_payment_method?(feature_type: :noncommercial) &&
          billable_entity.under_billing_attempts_limit? &&
          billable_entity.payment_amount > 0
      end

      # Duns users or businesses that don't have a payment method on file but an
      # active subscription
      #
      # These need to be dunned manually because removing payment sets their Zuora
      # account to `AutoPay: false`, which means Zuora will not attempt to bill
      # them or put them in dunning automatically
      sig { params(billable_entity: ::Billing::Types::Account).void }
      def self.dun_for_no_payment_method(billable_entity)
        GitHub.dogstats.increment("billing.run.autopay_false")
        message = "No payment method on file."

        throttle_writes do
          if billable_entity.is_a?(User)
            User.increment_counter(:billing_attempts, billable_entity.id)
            billable_entity.dun_subscription(message)
            billable_entity.update(billed_on: GitHub::Billing.today + 7.days)
          elsif billable_entity.is_a?(Business)
            Customer.increment_counter(:billing_attempts, billable_entity.customer_id)
            billable_entity.dun_subscription(message)
            billable_entity.customer&.update(billing_end_date: GitHub::Billing.today + 7.days)
          end
        end
      end

      # Logs information about the billable entity
      sig { params(billable_entity: ::Billing::Types::Account).void }
      def self.log_entity_information(billable_entity)
        data = {
          "code.namespace" => self.name,
          "code.function" => __method__.to_s,
          "gh.billing.billable_entity.plan_name" => billable_entity.plan.name,
          "gh.billing.billable_entity.billing_attempts" => billable_entity.billing_attempts,
          "gh.billing.billable_entity.billed_on" => billable_entity.billed_on,
          "gh.billing.billable_entity.has_valid_payment_method" => billable_entity.has_valid_payment_method?(feature_type: :noncommercial),
          "gh.billing.billable_entity.has_external_subscription" => billable_entity.external_subscription?,
        }

        # Log entity type specific fields
        if billable_entity.is_a?(User)
          data["gh.user.login"] = billable_entity.display_login
        elsif billable_entity.is_a?(Business)
          data["gh.business.slug"] = billable_entity.slug
          data["gh.business.name"] = billable_entity.name
        end

        # Log coupon information
        if coupon = billable_entity.coupon
          data["gh.billing.coupon.discount"] = coupon.discount
        end

        # Log coupon redemption information
        if coupon_redemption = billable_entity.coupon_redemption
          data["gh.billing.coupon_redemption.expires_at"] = coupon_redemption.expires_at
          data["gh.billing.coupon_redemption.expired"] = coupon_redemption.expired
          data["gh.billing.coupon_redemption.stale"] = coupon_redemption.stale?

          GitHub.dogstats.increment("billing.run.coupons", {
            tags: ["stale:#{coupon_redemption.stale?}"]
          })
        end

        GitHub.logger.info(data)
      end
    end
  end
end
