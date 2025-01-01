# typed: true
# frozen_string_literal: true

class CopilotForEnterpriseBetaMembershipMailer < CopilotBaseMailer
  self.mailer_name = "mailers/copilot_for_enterprise_beta"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  def waitlist_acceptance(membership)
    @membership = membership
    @header = "Your enterprise has been granted access to #{Copilot::ENTERPRISE_PRODUCT_NAME} beta."
    return unless @membership.feature_enabled?

    @is_admin_signup = membership.member.adminable_by?(membership.actor)
    @business = membership.member
    admin_emails = @business.admins.map do |admin|
      user_email(admin)
    end

    subject = "[GitHub] [#{@business.slug}] Welcome to GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} beta"

    premail(
      from: github_noreply,
      bcc: admin_emails,
      subject: subject,
    )
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    return unless @membership.feature_enabled?

    @membership.actor
  end
end
