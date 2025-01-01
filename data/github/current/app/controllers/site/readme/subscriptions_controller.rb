# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Site::Readme::SubscriptionsController < Site::Readme::BaseController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  def create
    email_address = params.fetch(:email, "").strip
    MailchimpReadmeNewsletterJob.perform_later(email_address: email_address) if GitHub.mailchimp_enabled?
    head :ok
  end
end
