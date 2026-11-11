# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MailchimpDeleteJob < ApplicationJob
  queue_as :mailchimp

  MailchimpTryLaterError = Class.new(StandardError)

  retry_on MailchimpTryLaterError

  # Options:
  #
  # email_address - String
  # user_id - Integer
  #
  def perform(email_address, user_id, options = {})
    @email_address = email_address
    @user_id       = user_id
    @options       = options.with_indifferent_access

    Failbot.push(
      job: self.class.name,
      user_id: user_id,
    )

    GitHub.dogstats.increment "mailchimp", tags: ["job:delete_email"]

    email = UserEmail.new(email: @email_address, user_id: @user_id)

    with_mailchimp_retries do
      mailchimp = GitHub::Mailchimp.new(email)
      GitHub::Mailchimp.list_ids.each do |list_id|
        mailchimp.ensure_subscriber_exists(list_id) do
          mailchimp.delete(list_id: list_id)
        end
      end
    end
  end

  private

  # Private: When MailChimp API calls fail due to 5xx server errors,
  # retry the call up to 25 times. Otherwise, raise an exception
  # and fail the job.
  def with_mailchimp_retries(&block)
    yield
  rescue GitHub::Mailchimp::Error => boom
    if GitHub::Mailchimp::ServerErrorStatuses.include?(boom.status_code)
      GitHub.dogstats.increment "mailchimp", tags: ["job:delete_email", "type:retry"]

      raise MailchimpTryLaterError
    else
      raise
    end
  end
end
