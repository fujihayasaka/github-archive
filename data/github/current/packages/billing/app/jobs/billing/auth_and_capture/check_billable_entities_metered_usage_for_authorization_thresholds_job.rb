# typed: true
# frozen_string_literal: true

# This job iterates through the billable accounts. It will process an authorization on all
# accounts meeting the criteria in the implemented `next_batch` method.
module Billing
  module AuthAndCapture
    class CheckBillableEntitiesMeteredUsageForAuthorizationThresholdsJob < BatchedJob
      queue_as :check_metered_usage_authorizations
      schedule interval: 8.hours, condition: -> { GitHub.billing_enabled? }

      exempt_from_tenant_context_requirement

      retry_on_dirty_exit

      before_enqueue do |_job|
        throw(:abort) unless GitHub.billing_enabled?
      end

      # Thresholds are in cents to align with our billing numbers
      # Ordered from smallest to largest
      THRESHOLDS = [5000, 20000].freeze # $50 $200

      # Strict timing rules for db queries within jobs requires limiting the upper bounds of next_batch query
      # in order to avoid being timed out
      QUERY_LIMIT = 100000

      def process_batch(batch, *args, **options)
        batch.each do |plan_subscription|
          next unless entity = plan_subscription.billable_entity
          next if entity.business? && entity.digital_front_door?

          authorizable_threshold = THRESHOLDS[0]

          total_usage_in_cents = total_metered_usage_in_cents(entity)

          if total_usage_in_cents >= authorizable_threshold
            Billing.domain.payment_authorizations.create(
              customer_id: entity.customer.id,
              origin: "metered_usage_threshold_check_job",
              skip_if_last_authorization_at: 1.month.ago,
            )
          end
        end
      end

      # Uses default BATCH_SIZE of 100
      def next_batch(timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        if FeatureFlag.vexi.enabled?(:use_billing_locked_rather_than_disabled, default: false)
          # This query includes users, organizations and businesses
          PlanSubscription
            .where.not(zuora_subscription_number: nil)
            .where("plan_subscriptions.id > ?", offset_item_id)
            .where("plan_subscriptions.id <= ?", offset_item_id + QUERY_LIMIT)
            .left_joins(:user)
            .left_joins(customer: :business)
            .where("(users.suspended_at IS NULL AND customers.locked_at IS NULL) OR (customers.billing_type = ? AND customers.locked_at IS NULL AND businesses.suspended_at IS NULL AND businesses.downgraded_at IS NULL)", Customer::BILLING_TYPE_CARD)
            .order("plan_subscriptions.id")
            .limit(BATCH_SIZE)
        else
          PlanSubscription
          .where.not(zuora_subscription_number: nil)
          .where("plan_subscriptions.id > ?", offset_item_id)
          .where("plan_subscriptions.id <= ?", offset_item_id + QUERY_LIMIT)
          .left_joins(:user)
          .left_joins(customer: :business)
          .where("(users.suspended_at IS NULL AND users.disabled = false) OR (customers.billing_type = ? AND businesses.suspended_at IS NULL AND businesses.downgraded_at IS NULL)", Customer::BILLING_TYPE_CARD)
          .order("plan_subscriptions.id")
          .limit(BATCH_SIZE)
        end
      end

      # There are two scenarios where scheduling another batch is required
      # 1. The current batch is full and the max id is less than PlanSubscription table max id
      # 2. The current batch is not full and the query limit id is less than PlanSubscription table max id
      def has_next_batch?(batch, **options)
        if batch.size == BATCH_SIZE
          PlanSubscription.maximum(:id).to_i > batch.map(&:id).max
        else
          PlanSubscription.maximum(:id).to_i > options[:offset_item_id] + QUERY_LIMIT
        end
      end

      # Improve performance by overwriting the default when we know all users up to the query limit were checked
      def next_batch_offset_item_id(batch, *args, **options)
        if batch.size < BATCH_SIZE
          options[:offset_item_id] + QUERY_LIMIT
        else
          batch.map(&:id).max
        end
      end

      private

      def total_metered_usage_in_cents(entity)
        Billing::UsageChecker.new(account: entity).total_usage_in_cents
      rescue Billing::Platform::Api::Error => e
        Failbot.report(e)
        0
      end
    end
  end
end
