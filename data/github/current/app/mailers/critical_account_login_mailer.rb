# typed: true
# frozen_string_literal: true

# CriticalAccountLoginMailer is a mailer that sends time sensitive emails.
# These time sensitive emails could contain codes for users to log in,
# links that have a set expiration, etc.
class CriticalAccountLoginMailer < ApplicationMailer
  extend T::Sig
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include ApplicationHelper

  self.delivery_job = AccountLogin::CriticalMailersDeliveryJob

  self.mailer_name = "mailers/account"
  helper :application

  # Some mailers do not use the primer layout, so we need to specify the layout for them
  layout proc {
    T.bind(self, CriticalAccountLoginMailer)

    case action_name.to_sym
    when :new_password
      "layouts/primer_layout"
    end
  }

  def self.resolve_tenant(action_name, args)
    case action_name.to_sym
    when :new_password
      user, * = args
      Business.find_by(id: user.business_id)
    else
      # fall back to current tenant context if set
      GitHub::CurrentTenant.get
    end
  end

  sig { params(user: User, email: String, link: String, hours_until_expiry: Integer, forced_reset: T::Boolean, new_password_reset_url: T.nilable(String)).void }
  def new_password(user, email, link, hours_until_expiry, forced_reset, new_password_reset_url = nil)
    @link = link
    @hours_until_expiry = hours_until_expiry
    @forced_reset = forced_reset
    @new_password_reset_url = new_password_reset_url || "#{GitHub.url}/password_reset"

    args = {
      to: user_email(user, email),
      subject: "[GitHub] Please reset your password",
    }
    premail(**args)
  end

  # An email sent to the given email address, containing a link that will allow un-linking the given address from
  # the given account
  sig { params(email: UserEmail, user: User, link: String).void }
  def email_unlink_verification(email, user, link)
    @email = email
    @user = user
    @link = link
    mail(
      from: github_noreply,
      to: email,
      subject: "[GitHub] Unlink this email",
    )
  end

  # When verified device enforcement is enabled, we deliver this email when a
  # sign in from an unverified device occurs. The code in this email is used
  # to complete the sign in
  #
  # device_name: the auto-generated device name based on the user agent
  # verification_code: the code that is used to complete sign in
  sig { params(user: User, device_name: String, verification_code: String).void }
  def verified_device_verification(user, device_name, verification_code)
    @user = user
    @device_name = device_name
    @verification_code = verification_code
    mail_to_primary_bcc_remaining_account_related_emails(
      template_name: :verified_device_verification,
      subject: "[GitHub] Please verify your device",
    )
  end
end
