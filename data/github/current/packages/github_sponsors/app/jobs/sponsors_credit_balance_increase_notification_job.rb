# typed: true
# frozen_string_literal: true

class SponsorsCreditBalanceIncreaseNotificationJob < ApplicationJob
  queue_as :billing

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  # Send a notification email when a Sponsors-invoiced org's credit balance is increased.
  #
  # sponsor - Sponsors-invoiced Organization whose credit balance was increased
  #
  # Returns a Boolean where true indicates an email was sent.
  def perform(sponsor:)
    return false unless GitHub.sponsors_enabled? && sponsor&.sponsors_invoiced?

    SponsorsPrimerMailer.credit_balance_increase_notification(
      sponsor: sponsor,
    ).deliver_later
    true
  end
end
