# typed: true
# frozen_string_literal: true

class DigitalFrontDoorMailer < ApplicationMailer
  self.mailer_name = "mailers/business/digital_front_door"

  helper :application
  helper :avatar
  helper :email_link_tracking

  layout "layouts/primer_layout"

  def authorization_failed(business)
    return unless business.has_failed_trial_authorization?

    @business = business
    @payment_method = @business.friendly_payment_method_name
    @subject = "We were unable to verify your identity using your #{@payment_method}"
    @footer_text = "You are receiving this email because we had a problem verifying your identity using your #{@payment_method}."
    @settings_url = enterprise_billing_payment_information_url(
                          @business,
                          host: GitHub.urls.host_name
                          )

    recipients = business_emails(@business, include_billing_managers: true)

    premail(
      from: github_noreply,
      bcc: recipients,
      subject: "[GitHub] " + @subject,
    )
  end
end
