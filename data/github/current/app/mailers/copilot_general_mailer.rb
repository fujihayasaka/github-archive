# typed: strict
# frozen_string_literal: true

class CopilotGeneralMailer < CopilotBaseMailer
  include UrlHelpers
  include UrlHelper

  self.mailer_name = "mailers/copilot_general"

  helper Primer::ViewHelper

  layout "layouts/copilot"

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
