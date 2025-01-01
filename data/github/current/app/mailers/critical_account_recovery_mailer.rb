# typed: true
# frozen_string_literal: true

# CriticalAccountRecoveryMailer is a mailer that sends time sensitive emails.
# These time sensitive emails could contain codes for users to log in,
# links that have a set expiration, etc.
class CriticalAccountRecoveryMailer < ApplicationMailer
  extend T::Sig
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.delivery_job = AccountLogin::CriticalMailersDeliveryJob

  self.mailer_name = "mailers/account_recovery"

  # Sends a OTP code to the user for account recovery
  sig { params(user: User, otp: String).void }
  def send_otp(user, otp)
    return if GitHub.enterprise?
    @user = user
    @otp = otp

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :send_otp,
      subject: "[GitHub] Two-factor lockout request",
    )
  end
end
