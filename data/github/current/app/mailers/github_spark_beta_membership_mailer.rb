# typed: true
# frozen_string_literal: true

class GitHubSparkBetaMembershipMailer < CopilotBaseMailer
  self.mailer_name = "mailers/github_spark"

  layout "layouts/github_spark"

  SUBJECT = "[GitHub] You have been granted access to the GitHub Spark preview"

  def waitlist_acceptance(membership)
    @membership = membership

    return unless @membership.feature_enabled?

    @header = T.let("You have been granted access to the GitHub Spark preview", T.nilable(String))
    @user_login = T.let(membership.actor.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(membership.actor),
      subject: SUBJECT,
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return unless @membership.feature_enabled?

    @membership.actor
  end
end
