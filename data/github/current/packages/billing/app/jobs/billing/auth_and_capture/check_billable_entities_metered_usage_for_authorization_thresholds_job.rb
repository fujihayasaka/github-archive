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

      # Net amount authorization threshold in cents
      THRESHOLD_IN_CENTS = 5000 # $50

      # Strict timing rules for db queries within jobs requires limiting the upper bounds of next_batch query
      # in order to avoid being timed out
      QUERY_LIMIT = 100000

      def process_batch(batch, *args, **options)
        user_plan_subscriptions, business_plan_subscriptions = batch.partition(&:billable_user?)
        GitHub::PrefillAssociations.prefill_associations(user_plan_subscriptions, { user: :customer })
        GitHub::PrefillAssociations.prefill_associations(business_plan_subscriptions, { customer: :business })

        batch.each do |plan_subscription|
          next unless entity = plan_subscription.billable_entity
          next if entity.suspended?
          next if entity.business? && entity.downgraded_to_free_plan?
          next if entity.business? && entity.digital_front_door?
          # If the organization is metered via azure, there's no need to authorize them as they have no metered usage associated to their credit card
          # This is only valid currently because we cannot authorize Azure subscriptions.
          next if entity.organization? && entity.metered_via_azure?

          checker = Billing::UsageChecker.new(account: entity)

          meets_net_threshold = net_usage_in_cents(checker) >= THRESHOLD_IN_CENTS

          if meets_net_threshold
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
        Billing::PlanSubscription
          .where.not(zuora_subscription_number: nil)
          .where("plan_subscriptions.id > ?", offset_item_id)
          .where("plan_subscriptions.id <= ?", offset_item_id + QUERY_LIMIT)
          .joins(:customer)
          .where("customers.zuora_account_number IS NOT NULL")
          .where("customers.locked_at IS NULL")
          .where("customers.billing_type IS NULL OR customers.billing_type = ?", Customer::BILLING_TYPE_CARD)
          .order("plan_subscriptions.id")
          .limit(BATCH_SIZE)
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

      sig { params(checker: Billing::UsageChecker).returns(Integer) }
      def net_usage_in_cents(checker)
        checker.total_usage_in_cents
      rescue Billing::Platform::Api::Error => e
        Failbot.report(e)
        0
      end
    end
  end
end
