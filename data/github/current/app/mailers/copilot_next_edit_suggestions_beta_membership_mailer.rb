# typed: true
# frozen_string_literal: true
class CopilotNextEditSuggestionsBetaMembershipMailer < CopilotBaseMailer
  self.mailer_name = "mailers/copilot_next_edit_suggestions"

  layout "layouts/copilot"

  SUBJECT = "[GitHub] You have been granted access to Copilot Next Edit Suggestions (NES) Beta"

  def waitlist_acceptance(membership)
    @membership = membership

    return unless @membership.feature_enabled?

    @header = T.let("You have been granted access to Copilot Next Edit Suggestions (NES) Beta", T.nilable(String))
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
