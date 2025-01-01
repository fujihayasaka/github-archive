# typed: true
# frozen_string_literal: true
class HelpHubEmailVerifiedSignInMailer < ApplicationMailer
  extend T::Sig

  # This email was deemed critical if signed-out users need to verify their email address in order to reach out to support.
  # We don't want to delay this email if the shared pool is backed up.
  # Updating the delivery job to use a specific queue and dedicated worker pool instead of the shared pool.
  self.delivery_job = HelpHub::CriticalMailersDeliveryJob
  self.mailer_name = "mailers/support"

  helper :application

  layout "layouts/primer_layout"

  # Sends a verification email to signed-out users accessing the support portal
  sig { params(email: String, code: String).void }
  def helphub_email_verified_sign_in_code_requested(email, code)
    @email = email
    @code = code
    premail(
      to: email,
      subject: "#{code} is your GitHub Support verification code"
    )
  end
end
