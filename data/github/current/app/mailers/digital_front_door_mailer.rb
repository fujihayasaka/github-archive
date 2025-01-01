# typed: true
# frozen_string_literal: true

class DigitalFrontDoorMailer < BusinessMailer

  self.mailer_name = "mailers/business/digital_front_door"

  def authorization_failed(business)
    return unless business.has_failed_trial_authorization?

    @business = business
    @payment_method = @business.friendly_payment_method_name
    @subject = "We were unable to verify your identity using your #{@payment_method}"
    @footer_text = "You are receiving this email because we had a problem verifying your identity using your #{@payment_method}."
    @settings_url = settings_billing_tab_enterprise_url(
                          @business,
                          tab: "payment_information",
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
