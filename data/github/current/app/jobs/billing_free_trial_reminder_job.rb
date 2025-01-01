# typed: true
# frozen_string_literal: true

class BillingFreeTrialReminderJob < BillingJob
  queue_as :billing

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  exempt_from_tenant_context_requirement

  # Blast emails to all users who have a free trial that will expire in 4 days and
  # skipping products whose free trial email is handled by the marketing nurture email.
  #
  # Instrumentation:
  #
  #   billing.free_trial_reminder.time  - Time it took to sends out the reminders.
  #   billing.free_trial_ending.count - Number of users that were notified.
  #
  def perform
    GitHub.dogstats.time("billing.reminders.free_trial_reminder_time") do
      usernames = []
      Billing::PendingSubscriptionItemChange
        .free_trial_expiring_internal_reminder_eligible
        .find_each do |subscription_item_change|
          user = subscription_item_change.user
          next if user.nil?

          BillingNotificationsMailer.free_trial_will_end_soon(user, subscription_item_change).deliver_now
          usernames << user.login
        end

      GitHub.dogstats.count("billing.reminders.free_trial_ending", usernames.size)
    end
  end
end
