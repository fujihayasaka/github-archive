# typed: true
# frozen_string_literal: true
class BitbucketServerMigrationsBetaMembershipMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/bitbucket_server_migrations"

  layout "layouts/primer_layout_minimal"

  SUBJECT = "Welcome to the Bitbucket Server migrations private beta!"

  def waitlist_acceptance(membership)
    @membership = membership

    premail(
      from: github_noreply,
      to: user_email(membership.actor),
      subject: SUBJECT,
    )
  end
end
