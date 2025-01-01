# typed: true
# frozen_string_literal: true

class CopilotCodeReviewBetaMailer < CopilotBaseMailer
  helper Primer::ViewHelper
  self.mailer_name = "mailers/copilot_code_review"
  layout "layouts/copilot_business_email"

  sig { params(membership: EarlyAccessMembership).returns(T.nilable(String)) }
  def individual_waitlist_acceptance(membership)
    @membership = membership
    @copilot_code_review_ga = FeatureFlag.vexi.enabled_or_raise?(:copilot_code_review_ga) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    return unless @membership.feature_enabled?
    return unless @membership.member.class.name == "User"

    subject = "You’ve been granted access to GitHub Copilot code review"
    @header = T.let("You’ve been granted access to GitHub Copilot code review", T.nilable(String))
    @user_login = T.let(@membership.member.display_login, T.nilable(String))

    premail(from: github_noreply, to: user_email(membership.member), subject: subject)
  end

  sig { params(membership: EarlyAccessMembership, admin: User).returns(T.nilable(String)) }
  def organization_waitlist_acceptance(membership, admin)
    @membership = membership
    @copilot_code_review_ga = FeatureFlag.vexi.enabled_or_raise?(:copilot_code_review_ga) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    member = @membership.member

    return unless @membership.feature_enabled?
    return unless member.is_a?(Organization)

    @member_type = "organization"
    subject = "Your organization has been granted access to GitHub Copilot code review"
    @header = T.let("Your organization has been granted access to GitHub Copilot code review", T.nilable(String))
    @user_login = T.let(admin.display_login, T.nilable(String))
    @org_name = T.let(member.display_login, T.nilable(String))

    copilot_user = Copilot::User.new(admin)
    @has_enterprise_access = copilot_user.has_ce_access?

    premail(from: github_noreply, to: user_email(admin), subject: subject)
  end

  sig { returns(T.nilable(::User)) }
  def mailable
    return unless @membership.feature_enabled?

    @membership.member
  end
end
