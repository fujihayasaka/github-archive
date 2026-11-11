# typed: true
# frozen_string_literal: true

class SecurityMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/security"

  def incident_notification(options = {})
    from = options[:from] || raise("from must be present")
    user = options[:user] || raise("user must be present")
    email = options[:email].presence || user.email || raise("email must be present")
    subject = options[:subject] || raise("subject must be present")
    body = options[:body] || raise("body must be present")

    # optionally extract other values from `options` for the template
    # @token = options[:token]

    mail(
      from: from,
      to: user_email(user, email),
      subject: subject,
      body: body,
    )
  end
end
