# typed: true
# frozen_string_literal: true

class CodeScanningAssessmentMailer < ApplicationMailer
  self.mailer_name = "mailers/code_scanning_assessment"

  layout "layouts/primer_layout"

  sig do
    params(
      actor: User,
      owner: Organization,
      assessment_number: Integer,
      status: String,
      num_vulnerabilities: Integer,
    ).returns(T.untyped)
  end
  def assessment_summary(actor, owner, assessment_number, status, num_vulnerabilities: 0)
    success = false

    begin
      result = ActiveRecord::Base.connected_to(role: :reading) do
        perform_assessment_summary(actor, owner, assessment_number, status, num_vulnerabilities)
      end
      success = true
    ensure
      GitHub.dogstats.increment("code_scanning.mailer.assessment_summary", tags: ["success:#{success}", "sent:#{!result.nil?}", "status:#{status}"])
    end
  end

  private

  sig do
    params(
      actor: User,
      owner: Organization,
      assessment_number: Integer,
      status: String,
      num_vulnerabilities: Integer,
    ).returns(T.untyped)
  end
  def perform_assessment_summary(actor, owner, assessment_number, status, num_vulnerabilities)
    return nil unless allow_sending_to_email?(actor, owner)

    @failed = status == "failed"
    owner_name = owner_display_name(owner)

    if @failed
      subject = "[#{owner_name}] Your code security risk assessment could not be completed"
      title = "We were unable to complete your code security risk assessment"
      @has_vulnerabilities = false
      reason = "code-scanning-assessment-failed"
    else
      num_vulnerabilities_display = num_vulnerabilities.zero? ? "No" : num_vulnerabilities
      title = "#{num_vulnerabilities_display} #{"vulnerability".pluralize(num_vulnerabilities)} found in"
      subject = "[#{owner_name}] Scan complete for your code security risk assessment"
      @has_vulnerabilities = !num_vulnerabilities.zero?
      reason = "code-scanning-assessment-complete"
    end

    send_assessment_email(
      actor:,
      owner:,
      assessment_number:,
      subject:,
      title:,
      reason:,
    )
  end

  sig do
    params(
      actor: User,
      owner: Organization,
      assessment_number: Integer,
      subject: String,
      title: String,
      reason: String,
    ).returns(T.untyped)
  end
  def send_assessment_email(actor:, owner:, assessment_number:, subject:, title:, reason:)
    @owner_name = owner_display_name(owner)
    @title = title
    @footer_links = footer_links
    @footer_text = "You are receiving this email because you requested a code security risk assessment for your organization."
    @header_text = "GitHub Code Security"
    @icon = "existing-vulnerability.png"
    @assessment_path = UrlHelpers.security_center_assessments_path(org: owner, feature: "code-security")

    message_id = "<code-scanning-assessments-#{@failed ? "failed" : "complete"}/#{owner.name}/#{assessment_number}@#{GitHub.urls.host_name}>"
    headers({
      "Message-Id" => message_id,
      "X-GitHub-Sender" => GitHub.trusted_oauth_apps_org_name,
      "X-GitHub-Recipient" => actor.display_login,
      "X-GitHub-Reason" => reason,
    })

    template = @failed ? "assessment_failed_summary" : "assessment_complete_summary"

    premail(
      from: github,
      to: user_email(actor, GitHub.newsies.email(actor, owner)),
      subject:,
      template_name: template,
    )
  end

  sig { params(owner: Organization).returns(String) }
  def owner_display_name(owner)
    owner.display_name.presence || owner.display_login
  end

  sig { params(user: User, owner: Organization).returns(T::Boolean) }
  def allow_sending_to_email?(user, owner)
    return false unless Notifications::Settings.watcher_email?(user)
    owner.user_can_receive_email_notifications?(user)
  end

  def footer_links
    [
      { url: "#{GitHub.url}/login", text: "Sign in to GitHub" },
      { url: UrlHelpers.settings_notification_preferences_url(host: GitHub.url), text: "Notification settings" },
    ]
  end
end
