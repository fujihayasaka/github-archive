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

      if !@user.feature_flag_enabled_or_raise?(:copilot_premium_usage_report_email) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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

      if !@user.feature_flag_enabled_or_raise?(:copilot_premium_usage_report_email) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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


  sig { params(user: User, entity: T.any(::Organization, ::Business), link: T.nilable(String)).void }
  def activity_report_download(user, entity, link)
    @user = T.let(user, T.nilable(User))
    @entity = T.let(entity, T.nilable(T.any(::Organization, ::Business)))
    @link = T.let(link, T.nilable(String))

    if @link.nil? || @link.empty?
      GitHub.logger.error(
        "No download link supplied",
        "gh.copilot.entity_type" => @entity_type,
        "gh.copilot.entity_id" => @entity&.id,
        "gh.user.id" => @user&.id
      )
      return
    end

    @entity_type = T.let(@entity.class.name.to_s.downcase, T.nilable(String))
    @entity_name = T.let(
      if @entity.is_a?(::Organization)
        @entity.display_login
      elsif @entity.is_a?(::Business)
        @entity.slug
      end,
      T.nilable(String)
    )

    email = user_email(@user)
    email_record = UserEmail.find_by(email: email)

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => __method__.to_s,
      "gh.user.id" => @user&.id,
      "gh.copilot.configurable_type" => @entity.class.name,
      "gh.copilot.configurable_id" => @entity&.id,
      "gh.copilot.activity_report.download_url" => @link,
      "gh.email_record.id" => email_record&.id,
    ) do

      GitHub.logger.info("Sending activity report link")

      premail(
        from: github_noreply,
        to: email,
        subject: "Your GitHub Copilot Activity report is ready"
      )
    end
  end

  sig { params(user: User, entity: T.any(::Organization, ::Business), csv_data: String, filename: String).void }
  def activity_report(user, entity, csv_data, filename)
    @user = T.let(user, T.nilable(User))
    @entity = T.let(entity, T.nilable(T.any(::Organization, ::Business)))
    @filename = T.let(filename, T.nilable(String))

    @entity_type = T.let(@entity.class.name.to_s.downcase, T.nilable(String))
    @entity_name = T.let(
      if @entity.is_a?(::Organization)
        @entity.display_login
      elsif @entity.is_a?(::Business)
        @entity.slug
      end,
      T.nilable(String)
    )

    email = user_email(@user)
    # We'll only expect this to find an email for an enterprise managed user
    # Otherwise, the email will be formatted like "user name <the_email_address>",
    # and the lookup below will fail.
    email_record = UserEmail.find_by(email: email)

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => __method__.to_s,
      "gh.user.id" => @user&.id,
      "gh.copilot.configurable_type" => @entity.class.name,
      "gh.copilot.configurable_id" => @entity&.id,
      "gh.email_record.id" => email_record&.id,
    ) do

      GitHub.logger.info("Sending activity report via email")

      attachments[@filename] = {
        mime_type: "text/csv",
        content: csv_data
      }

      premail(
        from: github_noreply,
        to: email,
        subject: "Your GitHub Copilot Activity report is ready"
      )
    end
  end

  sig { params(user: User, entity: T.any(::Organization, ::Business)).void }
  def activity_report_no_data(user, entity)
    @user = T.let(user, T.nilable(User))
    @entity = T.let(entity, T.nilable(T.any(::Organization, ::Business)))

    @entity_type = T.let(@entity.class.name.to_s.downcase, T.nilable(String))
    @entity_name = T.let(
      if @entity.is_a?(::Organization)
        @entity.display_login
      elsif @entity.is_a?(::Business)
        @entity.slug
      end,
      T.nilable(String)
    )

    email = user_email(@user)
    email_record = UserEmail.find_by(email: email)

    GitHub.logger.with_named_tags(
      "code.namespace" => self.class.name,
      "code.function" => __method__.to_s,
      "gh.user.id" => @user&.id,
      "gh.copilot.entity_type" => @entity_type,
      "gh.copilot.entity_id" => @entity&.id,
      "gh.email_record.id" => email_record&.id.to_s,
    ) do
      if @user.nil?
        GitHub.logger.error("Actor not found for activity report")
        return
      end

      GitHub.logger.info("Sending activity report no data email")

      premail(
        from: github_noreply,
        to: email,
        subject: "Information about your GitHub Copilot Activity report request"
      )
    end
  end

  sig { returns(T.nilable(T.any(::User, ::Organization, ::Business))) }
  def mailable
    @user
  end
end
