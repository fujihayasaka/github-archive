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
  extend T::Sig

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

    @sendgrid_smtp_api ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))

    # Categories are short lowercase strings to tag a type of email. They're
    # useful to compare and contrast open rates and click through in SendGrid.
    #
    # This also relies on SendGrid and the SMTP API:
    # http://sendgrid.com/docs/API_Reference/SMTP_API/index.html
    if has_header?("categories")
      @sendgrid_smtp_api["category"] = header["categories"]&.value.split(",")
    else
      @sendgrid_smtp_api.delete("category")
    end
    header["X-SMTPAPI"] = nil if header["X-SMTPAPI"]
    header["X-SMTPAPI"] = encoded_smtp_api_header
  end

  private

  # SendGrid's SMTP API works by sending a list of instructions as encoded
  # JSON into the X-SMTPAPI header. This attribute stores the Hash that gets
  # converted into encoded JSON.
  sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  attr_reader :sendgrid_smtp_api

  sig { returns(ApplicationMailer) }
  attr_reader :mailer


  delegate :message, to: :mailer
  delegate :header, to: :message

  sig { params(name: String).returns(T::Boolean) }
  def has_header?(name)
    header[name]&.value != nil
  end

  sig { returns(T.nilable(String)) }
  def encoded_smtp_api_header
    return nil unless sendgrid_smtp_api

    if !(T.must(sendgrid_smtp_api)["category"] && T.must(sendgrid_smtp_api)["category"].any?)
      return nil
    end

    json = GitHub::JSON.encode(T.must(sendgrid_smtp_api))
    # Add spaces in between {} and ,
    json.gsub!(/(["\]}])([,:])(["\[{])/, '\\1\\2 \\3')

    json
  end
end
