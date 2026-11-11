# typed: strict
# frozen_string_literal: true

module Copilot
  module Individuals
    # Finds individual Copilot Pro / Pro+ yearly subscription items that have a
    # pending cancellation taking effect 1 month or 1 week from now, and
    # dispatches Copilot::Individuals::YearlyDowngradeWarningJob to send the
    # appropriate reminder email.
    #
    # Annual billing for individual GitHub Copilot plans is being deprecated
    # in favor of monthly billing. When a user does not manually move to a
    # monthly plan, their annual subscription gets a pending cancellation that
    # downgrades them to Copilot Free. This scheduler dispatches reminder
    # emails so they have a chance to switch before that happens.
    #
    # The day-of email (yearly_downgrade_today) is dispatched from the
    # Copilot::Events::SUBSCRIPTION_CANCELLED hydro subscription handler when
    # the cancellation actually takes effect, not from this scheduler.
    class YearlyDowngradeWarningSchedulerJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC
      schedule interval: 24.hours, condition: -> { GitHub.copilot_for_individuals_enabled? }
      gate_with_feature_flag :copilot_yearly_downgrade_warning_email_job
      exempt_from_tenant_context_requirement

      BATCH_SIZE = T.let(100, Integer)
      REMINDER_DAYS_BEFORE = T.let([30, 7].freeze, T::Array[Integer])

      sig { void }
      def perform
        GitHub.logger.with_named_tags("code.function" => "perform") do
          GitHub.logger.info("Starting Copilot::Individuals::YearlyDowngradeWarningSchedulerJob")

          subscribable_ids = ::Billing::ProductUUID
            .where(
              product_type: ::Copilot::PRODUCT_TYPE,
              product_key: [::Copilot::INDIVIDUAL_PRO_PRODUCT_KEY, ::Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY],
              billing_cycle: ::User::BillingDependency::YEARLY_PLAN,
            )
            .pluck(:id)

          GitHub.logger.info "Loaded yearly Copilot ProductUUIDs",
            "gh.billing.product_uuid.ids": subscribable_ids

          target_dates = REMINDER_DAYS_BEFORE.map { |n| ::GitHub::Billing.today + n.days }

          # PendingSubscriptionItemChange and PendingPlanChange are in the
          # integrations schema domain while SubscriptionItem is in the users
          # domain – they cannot be joined in a single query.
          #
          # Step 1: find pending cancellations (quantity → 0) on target dates in
          # the integrations domain.
          pending_item_changes = ::Billing::PendingSubscriptionItemChange
            .joins(:pending_plan_change)
            .where(
              subscribable_type: ::Billing::ProductUUID.name,
              subscribable_id: subscribable_ids,
              quantity: 0,
            )
            .where(pending_plan_changes: { active_on: target_dates, is_complete: false })

          # Step 2: for each pending change, look up the matching active
          # subscription item in the users domain and dispatch in batches.
          total_dispatched = 0
          pending_item_changes.in_batches(of: BATCH_SIZE) do |batch|
            plan_subscription_ids = batch.pluck(:plan_subscription_id)

            subscription_item_ids = ::Billing::SubscriptionItem
              .where("subscription_items.quantity > 0")
              .with_product_uuid_type
              .where(
                plan_subscription_id: plan_subscription_ids,
                subscribable_id: subscribable_ids,
              )
              .distinct
              .pluck(:id)

            next if subscription_item_ids.empty?

            total_dispatched += subscription_item_ids.size
            Copilot::Individuals::YearlyDowngradeWarningJob.perform_later(subscription_item_ids)
          end

          GitHub.logger.info("Finished Copilot::Individuals::YearlyDowngradeWarningSchedulerJob",
                             "gh.copilot.yearly_downgrade.subscription_items_count": total_dispatched)
        end
      end
    end
  end
end
