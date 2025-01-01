# typed: strict
# frozen_string_literal: true

class TradeScreeningMailer < ApplicationMailer
  self.mailer_name = "mailers/trade_screening"

  helper :trade_controls, :text

  default from: -> { github_trade_appeals }
  default return_path: -> { github_trade_appeals }
  default subject: "GitHub and Trade Controls"

  sig { params(user: User).void }
  def individual_actor_allowed_status(user)
    mail(from: github_noreply, to: user_email(user))
  end

  sig { params(user: User).void }
  def individual_actor_not_allowed_status(user)
    mail(from: github_noreply, to: user_email(user))
  end

  sig { params(org: Organization).void }
  def restricted_free_organization_allowed_status(org)
    mail(to: (admin_emails(org) | billing_emails(org)))
  end

  sig { params(user: User).void }
  def individual_actor_profile_data_needs_fixing(user)
    mail(from: github_noreply, to: user_email(user))
  end

  # For internal SDN notifications only
  sig { params(account: T.any(User, Organization, Business), emails: T::Array[String]).void }
  def true_match_internal_notification(account:, emails:)
    @account = T.let(account, T.nilable(T.any(::User, ::Organization, ::Business)))
    return unless @account

    subject = "#{@account.display_login} - Account has received true_match SDN screening status."
    mail(from: github_noreply, to: emails, subject: subject)
  end

  # Send email message to microsoft trade support from stafftools
  sig { params(cc_email: String, subject: String, email_content: String, bcc_email: T.nilable(String)).void }
  def contact_microsoft_trade_help(cc_email:, subject:, email_content:, bcc_email:)
    @email_content = T.let(email_content, T.nilable(String))
    mail(
      from: github_trade_sap_bis,
      to: microsoft_trade_help,
      cc: cc_email,
      bcc: bcc_email&.split(","),
      subject: subject
    )
  end

  sig { params(external_uuid: T.nilable(String)).void }
  def trade_screening_48_hour_sla_breach(external_uuid)
    @external_uuid = T.let(external_uuid, T.nilable(String))
    mail(
      from: github_trade_sap_bis,
      to: microsoft_trade_help,
      subject: 'Account in "hit_in_review" status for 72 hours'
    )
  end

  sig { params(account: T.any(User, Organization, Business), emails: T::Array[String]).void }
  def sponsors_maintainer_restricted(account:, emails:)
    @account = account
    subject = "#{@account.display_login} - Sponsored Maintainer has been trade restricted."
    mail(from: github_noreply, to: emails, subject: subject)
  end
end
