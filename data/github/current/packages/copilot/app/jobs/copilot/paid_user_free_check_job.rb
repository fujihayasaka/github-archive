# typed: strict
# frozen_string_literal: true

module Copilot
  # Only paid users with a Copilot Pro subscription are eligible for having their subscription converted to
  # a free subscription and getting refunded. We do this so we dont accidentally downgrade users who are on
  # a higher tier of subscription (Pro+ or Max).
  class PaidUserFreeCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 8.hours, key: DEFAULT_LOCK_PROC
    schedule interval: 24.hours, condition: -> { GitHub.copilot_for_individuals_enabled? }
    gate_with_feature_flag :copilot_paid_user_free_check_job
    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      GitHub.logger.with_named_tags "code.function": "perform" do
        subscribable_ids = ::Billing::ProductUUID.where(
          product_type: Copilot::PRODUCT_TYPE,
          product_key: Copilot::INDIVIDUAL_PRO_PRODUCT_KEY,
        ).pluck(:id)

        GitHub.logger.info "Loaded ProductUUIDs",
          "gh.billing.product_uuid.product_type": Copilot::PRODUCT_TYPE,
          "gh.billing.product_uuid.product_key": Copilot::INDIVIDUAL_PRO_PRODUCT_KEY,
          "gh.billing.product_uuid.ids": subscribable_ids

        subscription_items = ::Billing::SubscriptionItem
          .active
          .with_product_uuid_type
          .where(subscribable_id: subscribable_ids)

        paid_user_count = 0

        subscription_items.find_in_batches(batch_size: 100) do |subscription_items|
          subscription_item_ids = subscription_items.pluck(:id)
          paid_user_count += subscription_item_ids.count

          Copilot::PaidUserFreeCheckProcessorJob.perform_later(
            subscription_item_ids,
          )
          Copilot::Individuals::TrialExpirationWarningJob.perform_later(
            subscription_item_ids,
          )
        end

        GitHub.logger.info("Finished Copilot::PaidUserFreeCheckJob", "gh.copilot.paid_users.count": paid_user_count)
      end
    end
  end
end
