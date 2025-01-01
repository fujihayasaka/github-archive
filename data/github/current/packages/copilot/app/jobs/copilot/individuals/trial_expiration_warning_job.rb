# typed: strict
# frozen_string_literal: true

module Copilot
  module Individuals
    class TrialExpirationWarningJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_individual_trial_expiration_email_job

      sig { params(subscription_item_ids: T::Array[Integer]).void }
      def perform(subscription_item_ids)
        GitHub.logger.with_named_tags("code.function" => "perform") do
          GitHub.logger.info("Starting Copilot::Individuals::TrialExpirationWarningJob")

          subscription_items = ::Billing::SubscriptionItem
                                 .where(id: subscription_item_ids)
                                 .where("free_trial_ends_on IS NOT NULL")
                                 .includes(:product_uuid, plan_subscription: :user)

          subscription_items.each do |subscription_item|
            # Spammy users have locked billing and cannot be converted to full subscriptions,
            # so let's not send them emails saying they'll be billed soon
            if subscription_item.user.spammy?
              GitHub.logger.info("Skipping cancellation emails for spammy user",
                                 "gh.user.id" => subscription_item.user.id)
              next
            end

            days_left_in_trial = (subscription_item.free_trial_ends_on - Date.current).to_i

            case days_left_in_trial
            when 14
              if subscription_item.pending_cancellation?
                GitHub.logger.info("Sending two weeks from cancellation email",
                                   "gh.user.id" => subscription_item.user.id)
                CopilotForIndividualsMailer.cancellation_reminder(subscription_item.user, subscription_item.free_trial_ends_on).deliver_later
              else
                GitHub.logger.info("Sending two weeks from scheduled payment email",
                                   "gh.user.id" => subscription_item.user.id,
                                   "gh.billing.product_uuid.id" => subscription_item.product_uuid.id,
                                   "gh.billing.billing_transaction.payment_type" => subscription_item.latest_billing_transaction&.payment_type)
                CopilotForIndividualsMailer
                  .scheduled_payment_reminder(subscription_item.user,
                                              subscription_item.product_uuid,
                                              subscription_item.latest_billing_transaction&.payment_type,
                                              subscription_item.free_trial_ends_on,
                                              days_left_in_trial)
                  .deliver_later
              end
            when 7
              if subscription_item.pending_cancellation?
                GitHub.logger.info("Sending one week from cancellation email",
                                   "gh.user.id" => subscription_item.user.id)
                CopilotForIndividualsMailer.cancellation_reminder(subscription_item.user, subscription_item.free_trial_ends_on).deliver_later
              else
                GitHub.logger.info("Sending one week from scheduled payment email",
                                   "gh.user.id" => subscription_item.user.id,
                                   "gh.billing.product_uuid.id" => subscription_item.product_uuid.id,
                                   "gh.billing.billing_transaction.payment_type" => subscription_item.latest_billing_transaction&.payment_type)
                CopilotForIndividualsMailer
                  .scheduled_payment_reminder(subscription_item.user,
                                              subscription_item.product_uuid,
                                              subscription_item.latest_billing_transaction&.payment_type,
                                              subscription_item.free_trial_ends_on,
                                              days_left_in_trial)
                  .deliver_later
              end
            when 1
              if subscription_item.pending_cancellation?
                GitHub.logger.info("Sending one day from cancellation email",
                                   "gh.user.id" => subscription_item.user.id)
                CopilotForIndividualsMailer.one_day_from_cancellation(subscription_item.user).deliver_later
              else
                GitHub.logger.info("Sending one day from scheduled payment email",
                                   "gh.user.id" => subscription_item.user.id,
                                   "gh.billing.product_uuid.id" => subscription_item.product_uuid.id,
                                   "gh.billing.billing_transaction.payment_type" => subscription_item.latest_billing_transaction&.payment_type)
                CopilotForIndividualsMailer
                  .one_day_from_scheduled_payment(subscription_item.user,
                                                  subscription_item.product_uuid,
                                                  subscription_item.latest_billing_transaction&.payment_type,
                                                  subscription_item.free_trial_ends_on)
                  .deliver_later
              end
            end
          end

          GitHub.logger.info "Finished Copilot::Individuals::TrialExpirationWarningJob",
                             subscription_items_count: subscription_items.count
        end
      end
    end
  end
end
