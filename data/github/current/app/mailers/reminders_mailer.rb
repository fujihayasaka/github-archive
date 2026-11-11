# typed: true
# frozen_string_literal: true

class RemindersMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/reminders"

  def waitlist_acceptance(membership)
    subject = "You're in! Get started with scheduled reminders 💖"

    settings = GitHub.newsies.settings(membership.actor)
    contact_email = user_email(membership.actor, settings.email(membership.member).address)

    @membership = membership

    mail(
      from: github_noreply,
      to: contact_email,
      subject: subject,
    )
  end
end
