# typed: true
# frozen_string_literal: true

class MailchimpReadmeNewsletterJob < ApplicationJob
  queue_as :mailchimp

  class MailchimpServerError < StandardError; end

  MAX_SERVER_ERROR_RETRIES = 25

  # ReadME newsletter list
  # https://us11.admin.mailchimp.com/lists/dashboard/overview?id=365253
  README_NEWSLETTER_LIST = "c816fd9565"

  retry_on(MailchimpServerError, wait: :polynomially_longer, attempts: MAX_SERVER_ERROR_RETRIES) do |_job, _error|
    GitHub.dogstats.increment "mailchimp", tags: ["job:readme_newsletter.retry"]
  end

  def perform(email_address:)
    GitHub.dogstats.increment "mailchimp", tags: ["job:readme_newsletter"]

    return unless (email_address =~ URI::MailTo::EMAIL_REGEXP).present?

    options = {
      body: {
        email_address: email_address,
        status: "subscribed",
      }
    }

    member_id = GitHub::Mailchimp.member_id(email_address)
    list = GitHub::Mailchimp.request.lists(README_NEWSLETTER_LIST)

    list.members(member_id).upsert(**options)
  rescue Gibbon::MailChimpError => boom
    return false if boom.status_code == 400
    raise MailchimpServerError if GitHub::Mailchimp::ServerErrorStatuses.include?(boom.status_code)
    raise
  end
end
