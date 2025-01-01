# typed: true
# frozen_string_literal: true

class EnterpriseMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/enterprise"

  helper :application

  layout "layouts/primer_layout"

  # Invites a user into a private-mode GitHub Enterprise Server instance.
  def invite_user(user, password_reset_link, password_reset_expires)
    time = Time.parse(password_reset_expires)
    @user               = user
    @reset_link         = password_reset_link
    @hours_until_expiry = ((time - Time.now) / 1.hour).round
    @url                = GitHub.url

    premail(
      to: user_email(user),
      subject: "[GitHub] Welcome to your GitHub Enterprise Server instance",
    )
  end

  # Sample result values :
  #   result = {enterprise_name: "my_enterprise", total_org_count: 150, failed_org_count: 26, total_pkg_count: 1200, url: GitHub.url}
  #   result = {enterprise_name: "my_enterprise", total_org_count: 150, failed_org_count: 0, total_pkg_count: 1200, url: GitHub.url}
  def packages_migration(user, result)
    @user = user
    @result = result

    premail(
      to: user_email(user),
      subject: "[GitHub] Your GitHub Enterprise Server packages migration is complete",
    )
  end
end
