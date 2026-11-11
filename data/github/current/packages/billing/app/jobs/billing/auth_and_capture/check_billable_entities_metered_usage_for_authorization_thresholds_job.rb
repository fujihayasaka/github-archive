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

      # Gross amount authorization threshold in cents
      GROSS_THRESHOLD_IN_CENTS = 5000 # $50

      # Strict timing rules for db queries within jobs requires limiting the upper bounds of next_batch query
      # in order to avoid being timed out
      QUERY_LIMIT = 100000

      def process_batch(batch, *args, **options)
        batch.each do |plan_subscription|
          next unless entity = plan_subscription.billable_entity
          next if entity.business? && entity.digital_front_door?
          # If the organization is metered via azure, there's no need to authorize them as they have no metered usage associated to their credit card
          # This is only valid currently because we cannot authorize Azure subscriptions.
          next if entity.organization? && entity.metered_via_azure?

          checker = Billing::UsageChecker.new(account: entity)

          meets_net_threshold = net_usage_in_cents(checker) >= THRESHOLD_IN_CENTS

          include_gross_usage = entity.feature_flag_enabled?(:billing_auth_thresholds_verify_gross_usage, default: false) && should_be_authorized_for_gross_usage(account: entity)
          meets_gross_threshold = include_gross_usage ? copilot_gross_usage_in_cents(checker) >= GROSS_THRESHOLD_IN_CENTS : false

          if meets_net_threshold || meets_gross_threshold
            Billing.domain.payment_authorizations.create(
              customer_id: entity.customer.id,
              origin: "metered_usage_threshold_check_job",
              skip_if_last_authorization_at: 1.month.ago,
              include_gross_usage: meets_gross_threshold,
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

      sig { params(checker: Billing::UsageChecker).returns(Integer) }
      def net_usage_in_cents(checker)
        checker.total_usage_in_cents
      rescue Billing::Platform::Api::Error => e
        Failbot.report(e)
        0
      end

      sig { params(checker: Billing::UsageChecker).returns(Integer) }
      def copilot_gross_usage_in_cents(checker)
        checker.total_gross_usage_in_cents(product_names: %w[copilot])
      rescue Billing::Platform::Api::Error => e
        Failbot.report(e)
        0
      end

      sig { params(account: Billing::Types::Account).returns((T::Boolean)) }
      def should_be_authorized_for_gross_usage(account:)
        if account.is_a?(Organization)
          copilot_org = ::Copilot::Organization.new(account)
          return copilot_org.on_free_copilot_enterprise_trial? || copilot_org.on_free_copilot_business_trial?
        elsif account.is_a?(Business)
          return account.has_ongoing_copilot_business_trial?
        end
        false
      end

    end
  end
end
