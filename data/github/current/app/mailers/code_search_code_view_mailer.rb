# typed: true
# frozen_string_literal: true

class CodeSearchCodeViewMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/code_search_code_view"

  layout "layouts/primer_layout"

  SUBJECT = "Welcome to the GitHub Code Search And Code View Beta!"

  def waitlist_acceptance(membership)
    @membership = membership

    premail(
      from: github_noreply,
      to: user_email(membership.actor),
      subject: SUBJECT,
    )
  end
end
