# typed: strict
# frozen_string_literal: true

class CopilotCodeReviewMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_code_review"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def code_review_enabled_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @header = T.let("You've been granted access to #{Copilot::COPILOT_CODE_REVIEW}", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))
    @user = T.let(user, T.nilable(User))

    subject = "[GitHub] You have been granted access to #{Copilot::COPILOT_CODE_REVIEW}"
    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: subject
    )
  end

  sig { params(organization: ::Organization, user: ::User).returns(String) }
  def code_review_disabled_for_user(organization, user)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(user, T.nilable(User))
    @header = T.let("Your access to #{Copilot::COPILOT_CODE_REVIEW} has been disabled", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(user.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(user, GitHub.newsies.email(user, organization).value),
      subject: "[GitHub] #{Copilot::COPILOT_CODE_REVIEW} has been disabled by your organization",
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return @user if @user.present?
    @organization if @organization.present?
  end
end
