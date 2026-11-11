# typed: true
# frozen_string_literal: true

class DeveloperProgramMembershipMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/developer_program_membership"

  # Public: Create a welcome email for a user that just joined the GitHub
  # Developer Program.
  #
  # user - The User to send a welcome email to.
  #
  # Returns a Mail instance to deliver.
  def welcome(user)
    @user = user

    mail(
      to: user_email(@user),
      from: github,
      subject: "Welcome to the GitHub Developer Program",
      categories: "welcome-github-developer-program",
    )
  end
end
