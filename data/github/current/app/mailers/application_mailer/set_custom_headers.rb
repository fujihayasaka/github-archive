# typed: strict
# frozen_string_literal: true

# ActionMailer callback to set custom headers for SendGrid and set the smtp_envelope_to property of the message based
# on the given destinations. This enables email-list like funcaionality instead of depending on a to, cc, and bcc.
#
# SendGrid is a third party email delivery service that GitHub uses to send
# email. SendGrid has a feature called the SMTP API that allows us to set
# custom headers on emails that we send. This is useful for tracking and
# categorizing emails.
#
# This callback is automatically registered by the
# `ApplicationMailer.after_action` method.
#
# Example:
#
#     class ApplicationMailer < ActionMailer::Base
#       after_action SetCustomHeaders
#     end
#
class ApplicationMailer::SetCustomHeaders
  DESTINATION_HEADER = "X-GitHub-Recipient-Address"

  sig { params(mailer: ApplicationMailer).void }
  def self.after(mailer)
    new(mailer).call
  end

  sig { params(mailer: ApplicationMailer).void }
  def initialize(mailer)
    @mailer = mailer
  end

  sig { void }
  def call
    if recipients = header["destinations"]&.value
      header[DESTINATION_HEADER] = recipients
      message.smtp_envelope_to = recipients.split(",")
    end
  end

  private

  sig { returns(ApplicationMailer) }
  attr_reader :mailer

  delegate :message, to: :mailer
  delegate :header, to: :message
end
