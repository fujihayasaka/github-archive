# typed: strict
# frozen_string_literal: true

class CopilotGeneralMailer < CopilotBaseMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers

  self.mailer_name = "mailers/copilot_general"

  helper Primer::ViewHelper

  layout "layouts/copilot"

  sig { params(user: User, download_url: String).void }
  def premium_usage_report(user, download_url)
    @user = T.let(user, T.nilable(User))
    @download_url = T.let(download_url, T.nilable(String))
    email = user_email(@user)
    email_record = UserEmail.find_by(email: email)

    GitHub.logger.with_named_tags(
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.user.id": @user&.id,
      "gh.premium_usage_report.download_url": @download_url,
      "gh.email_record.id": email_record&.id.to_s,
    ) do
      if @user.nil?
        GitHub.logger.error("exception.message": "User not found for premium usage report")
        return
      end

      if !@user.feature_enabled?(:copilot_premium_usage_report_email)
        GitHub.logger.info("User does not have the copilot_premium_usage_report_email feature flag enabled")
        return
      end

      GitHub.logger.info(
        "Sending premium usage report via email",
        "gh.user.id": @user.id,
        "gh.premium_usage_report.download_url": download_url
      )

      premail(
        from: github_noreply,
        to: email,
        subject: "Your GitHub Copilot premium usage report is ready to download"
      )
    end
  end

  sig { params(user: User).void }
  def premium_usage_report_no_data(user)
    @user = T.let(user, T.nilable(User))
    email = user_email(@user)
    email_record = UserEmail.find_by(email: email)

    GitHub.logger.with_named_tags(
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.user.id": @user&.id,
      "gh.premium_usage_report.download_url": nil,
      "gh.email_record.id": email_record&.id.to_s,
    ) do
      if @user.nil?
        GitHub.logger.error("exception.message": "User not found for premium usage report")
        return
      end

      if !@user.feature_enabled?(:copilot_premium_usage_report_email)
        GitHub.logger.info("User does not have the copilot_premium_usage_report_email feature flag enabled")
        return
      end

      premail(
        from: github_noreply,
        to: email,
        subject: "Information about your GitHub Copilot premium usage report request"
      )
    end
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    @user
  end
end
