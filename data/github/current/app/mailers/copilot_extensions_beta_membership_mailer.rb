# typed: true
# frozen_string_literal: true
class CopilotExtensionsBetaMembershipMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  helper Primer::ViewHelper
  self.mailer_name = "mailers/copilot_extensions"
  layout "layouts/copilot_business_email"

  SUBJECT = "[GitHub] You have been granted access to GitHub Copilot Extensions Limited Public Beta"
  BANNER_IMG_PATH = "images/email/copilot/extensions-banner.png"

  sig { params(membership: EarlyAccessMembership).returns(T.nilable(String)) }
  def individual_waitlist_acceptance(membership)
    @membership = membership
    @banner_img = BANNER_IMG_PATH

    return unless @membership.feature_enabled?
    return unless @membership.member.is_a?(User) && @membership.member.type == "User"

    @header = T.let("You have been granted access to GitHub Copilot Extensions Limited Public Beta", T.nilable(String))
    @user_login = T.let(@membership.member.display_login, T.nilable(String))

    premail(from: github_noreply, to: user_email(membership.member), subject: SUBJECT)
  end

  sig { params(membership: EarlyAccessMembership, admin: User).returns(T.nilable(String)) }
  def business_waitlist_acceptance(membership, admin)
    @membership = membership
    @banner_img = BANNER_IMG_PATH
    member = @membership.member

    return unless @membership.feature_enabled?
    return unless member.is_a?(Organization) || member.is_a?(Business)

    @header = T.let("You have been granted access to GitHub Copilot Extensions Limited Public Beta", T.nilable(String))
    @user_login = T.let(admin.display_login, T.nilable(String))
    if member.is_a?(Organization)
      @biz_or_org_name = T.let(member.display_login, T.nilable(String))
    else
      @biz_or_org_name = T.let(member.name, T.nilable(String))
    end

    premail(from: github_noreply, to: user_email(admin), subject: SUBJECT)
  end

  sig { params(membership: EarlyAccessMembership, admin: User).returns(T.nilable(String)) }
  def notify_admin_about_signup(membership, admin)
    @membership = membership
    @banner_img = BANNER_IMG_PATH
    member = @membership.member

    return unless member.is_a?(Organization) || member.is_a?(Business)

    subject = "Enable your organization to join the GitHub Copilot Extensions Limited Public Beta"
    @header = T.let(subject, T.nilable(String))
    @admin_login = T.let(admin.display_login, T.nilable(String))

    premail(from: github_noreply, to: user_email(admin), subject: "[GitHub] #{subject}")
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return unless @membership.feature_enabled?

    @membership.member
  end
end
