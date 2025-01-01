# typed: strict
# frozen_string_literal: true

module Copilot
  class PaidUserFreeCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    extend T::Sig

    locked_by timeout: 8.hours, key: DEFAULT_LOCK_PROC
    schedule interval: 24.hours, condition: -> { GitHub.copilot_for_individuals_enabled? }
    gate_with_feature_flag :copilot_paid_user_free_check_job

    sig { void }
    def perform
      GitHub.logger.with_named_tags "code.function": "perform" do
        subscribable_ids = ::Billing::ProductUUID.where(
          product_type: Copilot::PRODUCT_TYPE,
          product_key: Copilot::PRODUCT_KEY,
        ).pluck(:id)

        GitHub.logger.info "Loaded ProductUUIDs",
          "gh.billing.product_uuid.product_type": Copilot::PRODUCT_TYPE,
          "gh.billing.product_uuid.product_key": Copilot::PRODUCT_KEY,
          "gh.billing.product_uuid.ids": subscribable_ids
        chatterbox_say "Loaded #{subscribable_ids.count} ProductUUIDs " +
          "for #{Copilot::PRODUCT_TYPE}/#{Copilot::PRODUCT_KEY}"

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
        chatterbox_say "Finished Copilot::PaidUserFreeCheckJob with " +
          "#{paid_user_count} paid users"
      end
    end
  end
end
