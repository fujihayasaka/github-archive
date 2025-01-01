# typed: true
# frozen_string_literal: true

class ProjectNeutronBetaMembershipMailer < ApplicationMailer
  self.mailer_name = "mailers/project_neutron"

  layout "layouts/neutron"

  ACCEPT_SUBJECT = "[GitHub] You have been granted access to GitHub Models limited public beta"
  JOIN_SUBJECT   = "[GitHub] You have joined the GitHub Models limited public beta waitlist"

  def waitlist_join(membership)
    @membership = membership
    return unless @membership.actor.feature_enabled?(:project_neutron_playground_waitlist_join_email)

    @header = T.let("You have joined the GitHub Models limited public beta waitlist", T.nilable(String))
    @user_login = T.let(membership.actor.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(membership.actor),
      subject: JOIN_SUBJECT,
    )
  end

  def waitlist_acceptance(membership)
    @membership = membership

    return unless @membership.feature_enabled?

    @header = T.let("You have been granted access to GitHub Models limited public beta", T.nilable(String))
    @user_login = T.let(membership.actor.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(membership.actor),
      subject: ACCEPT_SUBJECT,
    )
  end
end
