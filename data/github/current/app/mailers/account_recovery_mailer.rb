# typed: true
# frozen_string_literal: true

class AccountRecoveryMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/account_recovery"

  def confirm_request_completed(user, id, token)
    return if GitHub.enterprise?

    @user = user
    @url = two_factor_recovery_abort_request_url(id, token)

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :request_completed,
      subject: "[GitHub] Two-factor lockout request completed",
    )
  end

  def successful_login_detected(user)
    return if GitHub.enterprise?

    @user = user
    @support_link = contact_url(form: { subject: "Account recovery cancelled - @#{user.display_login}" })

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :successful_login,
      subject: "[GitHub] Two-factor lockout request cancelled",
    )
  end

  def request_approved_by_staff(user, id, abort_token, continue_token, emails = nil)
    return if GitHub.enterprise?

    @user = user
    @orgs_requiring_two_factor = user.organizations.select { |org| org.two_factor_requirement_enabled? }

    @abort_url = two_factor_recovery_abort_request_url(id, abort_token)
    @continue_url = two_factor_recovery_continue_url(id, continue_token)
    payload = {
      template_name: :request_approved_by_staff,
      subject: "[GitHub] Account recovery request approved",
    }
    if emails.blank?
      mail_to_primary_bcc_remaining_account_related_emails(**payload)
    else
      primary_email = emails.shift
      mail(payload.merge({ to: primary_email, bcc: emails.present? ? emails : [] }))
    end
  end

  def request_declined_by_staff(user)
    return if GitHub.enterprise?

    @user = user
    @support_link = contact_url(form: { subject: "Account recovery declined - @#{user.display_login}" })

    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :request_declined_by_staff,
      subject: "[GitHub] Account recovery request declined",
    )
  end
end
