# typed: true
# frozen_string_literal: true

# This job iterates through the billable accounts. It will process an authorization on all
# accounts meeting the criteria in the implemented `next_batch` method.
module Billing
  module AuthAndCapture
    class CheckBillableEntitiesMeteredUsageForAuthorizationThresholdsJob < BatchedJob
      queue_as :check_metered_usage_authorizations
      schedule interval: 8.hours, condition: -> { GitHub.billing_enabled? }

      retry_on_dirty_exit

      before_enqueue do |_job|
        throw(:abort) unless GitHub.billing_enabled?
      end

      # Thresholds are in cents to align with our billing numbers
      # Ordered from smallest to largest
      THRESHOLDS = [5000, 20000].freeze # $50 $200
      METERED_PRODUCTS = %w[actions packages shared_storage codespaces git_lfs ghec ghas].freeze

      # Strict timing rules for db queries within jobs requires limiting the upper bounds of next_batch query
      # in order to avoid being timed out
      QUERY_LIMIT = 100000

      def process_batch(batch, *args, **options)
        batch.each do |plan_subscription|
          next unless entity = plan_subscription.billable_entity
          next unless entity.can_be_authorized?

          # Condense all metered product usage into one total
          total_usage_in_cents = Billing::UsageChecker.new(
            account: entity,
            product_names: METERED_PRODUCTS
          ).total_usage_in_cents

          # Identify the maximum threshold reached for entity
          next if total_usage_in_cents < THRESHOLDS[0]
          threshold_in_cents = THRESHOLDS[0]
          THRESHOLDS.each do |threshold|
            if total_usage_in_cents >= threshold
              threshold_in_cents = threshold
            else
              break
            end
          end
          authorize_entity(entity, threshold_in_cents)
        end
      end

      def authorize_entity(entity, threshold_in_cents)
        # Only create an authorization if we have not already this pay period
        existing_authorization = Billing::BillingTransaction.where({
          user_id: entity.business? ? nil : entity.id,
          customer_id: entity.customer.id,
          transaction_type: :authorization,
          amount_in_cents: threshold_in_cents,
        }).where("created_at > ?", 1.month.ago).exists?

        unless existing_authorization
          Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: entity.id, amount_in_cents: threshold_in_cents, is_business: entity.business?, origin: self.class.name)
        end
      end

      # Uses default BATCH_SIZE of 100
      def next_batch(timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
        # This query includes users, organizations and businesses
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

      # There are two scenarios where scheduling another batch is required
      # 1. The current batch is full and the max id is less than PlanSubscription table max id
      # 2. The current batch is not full and the query limit id is less than PlanSubscription table max id
      def has_next_batch?(batch, **options)
        if batch.size == BATCH_SIZE
          PlanSubscription.maximum(:id) > batch.map(&:id).max
        else
          PlanSubscription.maximum(:id) > options[:offset_item_id] + QUERY_LIMIT
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
    end
  end
end
