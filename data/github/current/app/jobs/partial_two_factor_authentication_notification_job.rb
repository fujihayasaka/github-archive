# typed: true
# frozen_string_literal: true

class PartialTwoFactorAuthenticationNotificationJob < ApplicationJob
  queue_as :partial_two_factor_authentication_notification

  retry_on_dirty_exit

  def perform(partial_2fa_record, primary_email, bcc_emails)
    user = partial_2fa_record.user
    return unless user

    completed_2fa_record = user.authentication_records.
      web_sign_ins.
      same_device_as(partial_2fa_record).
      subsequent_to(partial_2fa_record).
      order(created_at: :desc).
      limit(1).first

    unless completed_2fa_record
      AccountMailer.unexpected_incomplete_sign_in(partial_2fa_record, primary_email, bcc_emails).deliver_now
      user.instrument_partial_two_factor_email_followup partial_2fa_record
    end

    GitHub.dogstats.increment("partial_2fa_sign_ins", tags: ["eventual_success:#{!!completed_2fa_record}"])
  end
end
