# typed: true
# frozen_string_literal: true

class MailchimpUnsubscribeJob < ApplicationJob
  queue_as :mailchimp

  MailchimpTryLaterError = Class.new(StandardError)
  retry_on MailchimpTryLaterError

  # Options:
  #
  # user_id       - User ID
  # email_address - String
  #
  def perform(user_id, email_address, options = {})
    @user_id       = user_id
    @user          = User.find_by(id: user_id)
    @email_address = email_address
    @email         = UserEmail.find_by(email: email_address)
    @options       = options.with_indifferent_access

    Failbot.push(
      job: self.class.name,
      user: @user.try(:login),
      user_id: user_id,
      email_id: @email.try(:id),
    )

    GitHub.dogstats.increment "mailchimp", tags: ["job:unsubscribe"]
    return unless @user

    # Use the found UserEmail record or instantiate a ghost email in
    # the case where the email address was already deleted.
    email = @email || UserEmail.new(email: @email_address, user: @user)

    return if email.stealth?

    with_mailchimp_retries do
      mailchimp = GitHub::Mailchimp.new(email)
      GitHub::Mailchimp.list_ids.each do |list_id|
        mailchimp.ensure_subscriber_exists(list_id) do
          mailchimp.unsubscribe(list_id: list_id)
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
      GitHub.dogstats.increment "mailchimp", tags: ["job:unsubscribe", "type:retry"]

      raise MailchimpTryLaterError
    else
      raise
    end
  end
end
