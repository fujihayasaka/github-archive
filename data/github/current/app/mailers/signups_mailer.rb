# typed: true
# frozen_string_literal: true

class SignupsMailer < AccountMailer
  self.mailer_name = "mailers/signups"
  self.delivery_job = SignupsDeliveryJob

  layout "layouts/primer_layout", only: [:email_verification, :launch_code_verification, :accountless_code_verification]

  LAUNCH_CODE_METRICS_PARAM = "via_launch_code_email"

  def email_verification(email)
    @user  = email.user
    @email = email

    @cta_url = user_confirm_verification_email_url(
      @user.display_login,
      @email.id,
      @email.verification_token,
    )

    @cta_tracking_url = ga_campaign_url(
      @cta_url,
      source: "verification-email",
      medium: "email",
      campaign: "github-email-verification",
      content: "html",
    )

    @footer_links = [
      { url: settings_email_preferences_url, text: "Email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]

    premail(
      to: user_email(@user, @email.to_s),
      subject: "[GitHub] Please verify your email address.",
    )
  end

  def launch_code_verification(email, invitation_token: nil, repo_invitation_token: nil)
    @email = email
    @user  = email.user

    @fallback_url = user_confirm_verification_email_url(
      @user.display_login,
      @email.id,
      @email.verification_token,
      LAUNCH_CODE_METRICS_PARAM => true,
    )

    @verification_page_url = account_verifications_url(:invitation_token => invitation_token, :repo_invitation_token => repo_invitation_token, LAUNCH_CODE_METRICS_PARAM => true)

    @footer_links = [
      { url: settings_email_preferences_url, text: "Email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]

    premail(
      to: user_email(@user, @email.to_s),
      subject: "🚀 Your GitHub launch code",
    )
  end

  def accountless_code_verification(verification_id, email_address, verification_token, invitation_token: nil, repo_invitation_token: nil)
    @verification_id = verification_id
    @verification_token = verification_token
    @fallback_url = accountless_confirm_account_verifications_url(verification: verification_id, token: verification_token)

    @verification_page_url = account_verifications_url(LAUNCH_CODE_METRICS_PARAM => true, :verification => @verification_id)

    @footer_links = [
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]

    premail(
      to: email_address,
      subject: "🚀 Your GitHub launch code",
    )
  end
end
