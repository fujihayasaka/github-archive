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

  # Enterprise admin emails
  sig { params(organization: ::Organization, admin: ::User).returns(String) }
  def code_review_enabled_for_org_admin(organization, admin)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(admin, T.nilable(User))
    @header = T.let("Your developers can start using #{Copilot::COPILOT_CODE_REVIEW} in pull requests today.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(admin.display_login, T.nilable(String))

    subject = "Copilot code review is now enabled for #{organization.display_login}"
    premail(
      from: github_noreply,
      to: user_email(admin, GitHub.newsies.email(admin, organization).value),
      subject: "[GitHub] #{subject}",
    )
  end

  sig { params(organization: ::Organization, admin: ::User).returns(String) }
  def code_review_no_policy_for_org_admin(organization, admin)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(admin, T.nilable(User))
    @header = T.let("Your enterprise made #{Copilot::COPILOT_CODE_REVIEW} available, finish setup to let your team use it.", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(admin.display_login, T.nilable(String))

    subject = "Copilot code review is now available for #{organization.display_login}"
    premail(
      from: github_noreply,
      to: user_email(admin, GitHub.newsies.email(admin, organization).value),
      subject: "[GitHub] #{subject}",
    )
  end

  sig { params(organization: ::Organization, admin: ::User).returns(String) }
  def code_review_disabled_for_org_admin(organization, admin)
    @organization = T.let(organization, T.nilable(::Organization))
    @user = T.let(admin, T.nilable(User))
    @header = T.let("#{Copilot::COPILOT_CODE_REVIEW} access disabled for your organization", T.nilable(String))
    @organization_login = T.let(organization.display_login, T.nilable(String))
    @user_login = T.let(admin.display_login, T.nilable(String))

    premail(
      from: github_noreply,
      to: user_email(admin, GitHub.newsies.email(admin, organization).value),
      subject: "[GitHub] Copilot code review access disabled for your organization"
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return @user if @user.present?
    @organization if @organization.present?
  end
end
