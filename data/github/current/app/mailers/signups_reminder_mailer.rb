# typed: true
# frozen_string_literal: true

class SignupsReminderMailer < AccountMailer
  self.mailer_name = "mailers/signups"

  layout "layouts/primer_layout", only: [:email_verification, :launch_code_verification]

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
      source: "verification-email-reminder",
      medium: "email",
      campaign: "github-email-verification-reminder",
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
      subject: "[GitHub] Reminder: Please verify your email address.",
    )
  end

  def launch_code_verification(email)
    @email = email
    @user  = email.user

    @fallback_url = user_confirm_verification_email_url(
      @user.display_login,
      @email.id,
      @email.verification_token,
      SignupsMailer::LAUNCH_CODE_METRICS_PARAM => true,
    )

    @verification_page_url = account_verifications_url(
      SignupsMailer::LAUNCH_CODE_METRICS_PARAM => true,
    )

    @footer_links = [
      { url: settings_email_preferences_url, text: "Email preferences" },
      { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" },
      { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" },
      { url: login_url, text: "Sign in to GitHub" },
    ]

    premail(
      to: user_email(@user, @email.to_s),
      subject: "🚀 Reminder: Your GitHub launch code",
    )
  end
end
