# typed: true
# frozen_string_literal: true

class ResearchParticipantsMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/research_participants"

  layout "layouts/primer_layout"

  def invite_user(user, email, password_reset_link, password_reset_expires)
    time = Time.parse(password_reset_expires)
    @user = user
    @reset_link = password_reset_link
    @hours_until_expiry = ((time - Time.now) / 1.hour).round
    @url = GitHub.url

    premail(
      to: email,
      subject: "[GitHub] Welcome to GitHub Research!",
    )
  end
end
