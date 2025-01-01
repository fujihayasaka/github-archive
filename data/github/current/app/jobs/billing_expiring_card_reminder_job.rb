# typed: true
# frozen_string_literal: true

class BillingExpiringCardReminderJob < BillingJob
  queue_as :billing

  discard_on ActiveRecord::RecordNotFound

  def perform(account)
    return unless account&.should_remind_about_expiring_card?

    BillingNotificationsMailer.credit_card_will_expire_soon(account).deliver_later

    with_write { account.payment_method.increment!(:expiration_reminders) }
    GitHub.dogstats.increment("billing.reminders.card_expiring")
  end
end
