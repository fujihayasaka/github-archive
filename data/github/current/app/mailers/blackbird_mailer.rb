# typed: true
# frozen_string_literal: true

class BlackbirdMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/blackbird"

  layout "layouts/primer_layout"

  SUBJECT = "Welcome to the GitHub Code Search Technology Preview!"

  def waitlist_acceptance(membership)
    @membership = membership

    premail(
      from: github_noreply,
      to: user_email(membership.actor),
      subject: SUBJECT,
    )
  end
end
