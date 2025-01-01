# typed: strict
# frozen_string_literal: true

module Copilot
  class PaidUserFreeCheckProcessorJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    gate_with_feature_flag :copilot_paid_user_free_check_job

    sig { params(subscription_item_ids: T::Array[Integer]).void }
    def perform(subscription_item_ids)
      refund_enabled = GitHub.flipper[:copilot_paid_user_free_check_job_refund].enabled?

      GitHub.logger.with_named_tags(
        "code.function": "perform",
        "gh.copilot.paid_user.free_check_job.refund_enabled": refund_enabled,
      ) do
        refunded = Set.new

        subscription_item_ids.each do |subscription_item_id|
          GitHub.logger.with_named_tags(
            "gh.billing.subscription_item.id": subscription_item_id,
          ) do
            GitHub.logger.info "Processing SubscriptionItem"
            GitHub.dogstats.increment "copilot.paid_user_free_check"

            subscription_item = ::Billing::SubscriptionItem.find_by(
              id: subscription_item_id,
            )

            unless subscription_item
              GitHub.logger.error "No SubscriptionItem found"
              return
            end

            user = subscription_item.user
            copilot_user = Copilot::User.new(user)
            free_user = copilot_user.free_user

            if free_user
              was_subscribed = free_user.subscribed?
              with_write { free_user.subscribe }

              if refund_enabled
                GitHub.logger.info "Found FreeUser, refunding",
                  "gh.copilot.free_user.id": free_user.id,
                  "gh.copilot.free_user.free_user_type": free_user.free_user_type,
                  "gh.copilot.free_user.subscribed": was_subscribed,
                  "gh.user.id": user.id
                GitHub.dogstats.increment "copilot.paid_user_free_check.refund",
                  tags: [
                    "free_user_type:#{free_user.free_user_type}",
                    "subscribed:#{free_user.subscribed?}",
                  ]

                with_write do
                  subscription_item.cancel_and_refund!(allow_cancelling_iap: true)
                end

                CopilotFreeUserMailer
                  .paid_user_became_free(user)
                  .deliver_later

                refunded << user.id
              else
                GitHub.logger.info "Found FreeUser, would refund",
                  "gh.copilot.free_user.id": free_user.id,
                  "gh.copilot.free_user.free_user_type": free_user.free_user_type,
                  "gh.copilot.free_user.subscribed": was_subscribed,
                  "gh.user.id": user.id
                GitHub.dogstats.increment "copilot.paid_user_free_check.dry_run",
                  tags: [
                    "free_user_type:#{free_user.free_user_type}",
                    "subscribed:#{free_user.subscribed?}",
                  ]
              end

              next
            end

            GitHub.logger.info "User is nominal",
              "gh.user.id": user.id
          end
        end

        if refunded.any?
          chatterbox_say "Refunded #{refunded.size} users: #{refunded.to_a.join(', ')}"
        end
      end
    end
  end
end
