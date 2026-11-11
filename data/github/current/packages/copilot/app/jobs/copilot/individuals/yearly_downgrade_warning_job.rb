# typed: strict
# frozen_string_literal: true

module Copilot
  module Individuals
    # Sends reminder emails to individual Copilot users on a yearly Copilot Pro
    # or Pro+ subscription that has a pending cancellation (i.e. they will be
    # automatically downgraded to Copilot Free on the cancellation's active_on
    # date).
    #
    # Two emails are sent based on how many days remain until the pending
    # cancellation takes effect:
    #   - 30 days: yearly_downgrade_one_month_warning
    #   - 7 days:  yearly_downgrade_one_week_warning
    #
    # The day-of email (yearly_downgrade_today) is dispatched from the
    # Copilot::Events::SUBSCRIPTION_CANCELLED hydro subscription handler in
    # config/instrumentation/hydro/subscriptions/copilot_for_individuals.rb
    # when the cancellation actually takes effect.
    class YearlyDowngradeWarningJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_yearly_downgrade_warning_email_job
      exempt_from_tenant_context_requirement

      sig { params(subscription_item_ids: T::Array[Integer]).void }
      def perform(subscription_item_ids)
        GitHub.logger.with_named_tags("code.function" => "perform") do
          GitHub.logger.info("Starting Copilot::Individuals::YearlyDowngradeWarningJob")

          subscription_items = ::Billing::SubscriptionItem
                                 .where(id: subscription_item_ids)
                                 .includes(:subscribable, plan_subscription: :user)

          processed_count = 0

          subscription_items.each do |subscription_item|
            user = subscription_item.user

            # Spammy users have locked billing and cannot be converted to full subscriptions,
            # so let's not send them emails about an upcoming downgrade.
            if user.spammy?
              GitHub.logger.info("Skipping yearly downgrade warning emails for spammy user",
                                 "gh.user.id" => user.id)
              next
            end

            subscribable = subscription_item.subscribable
            unless subscribable.is_a?(::Billing::ProductUUID) &&
                   subscribable.product_type == ::Copilot::PRODUCT_TYPE &&
                   subscribable.billing_cycle == ::User::BillingDependency::YEARLY_PLAN
              next
            end

            pending_change = subscription_item.pending_subscription_item_change
            next unless pending_change&.cancellation?

            days_until_downgrade = (pending_change.active_on - ::GitHub::Billing.today).to_i

            case days_until_downgrade
            when 30
              GitHub.logger.info("Sending one month from yearly downgrade email",
                                 "gh.user.id" => user.id,
                                 "gh.billing.subscription_item.id" => subscription_item.id,
                                 "gh.billing.product_uuid.id" => subscribable.id)
              ::CopilotForIndividualsMailer
                .yearly_downgrade_one_month_warning(user)
                .deliver_later
              processed_count += 1
            when 7
              GitHub.logger.info("Sending one week from yearly downgrade email",
                                 "gh.user.id" => user.id,
                                 "gh.billing.subscription_item.id" => subscription_item.id,
                                 "gh.billing.product_uuid.id" => subscribable.id)
              ::CopilotForIndividualsMailer
                .yearly_downgrade_one_week_warning(user)
                .deliver_later
              processed_count += 1
            end
          end

          GitHub.logger.info "Finished Copilot::Individuals::YearlyDowngradeWarningJob",
                             subscription_items_count: subscription_items.count,
                             emails_sent_count: processed_count
        end
      end
    end
  end
end
