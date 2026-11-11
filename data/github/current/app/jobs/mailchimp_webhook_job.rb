# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MailchimpWebhookJob < ApplicationJob
  queue_as :mailchimp

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def initialize(type = nil, email_address = nil, options = {})
    @email_address = email_address
    @email         = UserEmail.find_by(email: @email_address)
    @user          = @email.try(:user)
    @webhook_type  = type
    @options       = options

    Failbot.push(
      job: self.class.name,
      user: @user.try(:login),
      email_id: @email.try(:id),
    )

    super
  end

  def perform(*args)
    GitHub.dogstats.increment "mailchimp", tags: ["job:incoming_webhook"]
    unless @email
      raise GitHub::Mailchimp::WebhookError,
        "Missing UserEmail"
    end

    case @webhook_type.to_s
    when "unsubscribe"
      unsubscribe_webhook
    when "cleaned"
      bounce_webhook
    else
      raise GitHub::Mailchimp::WebhookError,
        "Unsupported hook '#{@webhook_type.inspect}'"
    end
  end

  def unsubscribe_webhook
    with_write { NewsletterPreference.set_to_transactional(user: @user) }
  end

  def bounce_webhook
    # marking as a hard bounce
    # see http://kb.mailchimp.com/delivery/deliverability-research/soft-vs-hard-bounces
    with_write { @email.mark_as_bouncing!(source: :mailchimp) }
  end
end
