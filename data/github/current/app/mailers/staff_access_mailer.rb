# typed: true
# frozen_string_literal: true

class StaffAccessMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/staff_access"

  def repo_access_requested(request, admin_logins)
    @request = request
    @repo = request.accessible
    @approvals_url = repository_access_request_url(id: request.id, repository: @repo, user_id: @repo.owner)
    admins = admin_logins.map { |a| User.find_by(login: a) }
    recipients = build_admin_recipients_list(@repo.owner, admins)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Staff access requested for #{@repo.name_with_display_owner}",
    )
  end

  def repo_unlock_request_accepted(grant)
    repo = grant.accessible
    stafftools_url = security_stafftools_repository_url(repo.owner, repo)
    request_accepted(grant, "unlock #{repo.name_with_display_owner}", stafftools_url)
  end

  def repo_unlock_request_denied(request)
    repo = request.accessible
    stafftools_url = security_stafftools_repository_url(repo.owner, repo)
    request_denied(request, "unlock #{repo.name_with_display_owner}", stafftools_url)
  end

  def impersonation_notification(user, reason, admin_login)
    return unless GitHub.enterprise?

    @user = user
    @reason = reason
    @business_name = GitHub.global_business.name
    @admin_login = admin_login
    mail(
      from: github,
      to: @user.email,
      subject: "[GitHub] Administrative Impersonation notification",
      template_name: "impersonation_notification",
    )
  end

  def impersonation_access_requested(request)
    @request = request
    @user = request.accessible
    @approvals_url = user_staff_access_request_url(@user, request)

    mail(
      to: user_email(@user),
      # Disable rubocop because we want to use the login here for anything staff/stafftools adjacent
      subject: "[GitHub] Staff access to @#{@user} requested", # rubocop:disable GitHub/DoNotAllowLogin
    )
  end

  def impersonation_request_accepted(grant)
    user = grant.accessible
    stafftools_url = "#{GitHub.stafftools_url}#{stafftools_user_overview_path(user)}"
    # Disable rubocop because we want to use the login here for anything staff/stafftools adjacent
    request_accepted(grant, "log in as @#{user}", stafftools_url) # rubocop:disable GitHub/DoNotAllowLogin
  end

  def impersonation_request_denied(request)
    user = request.accessible
    stafftools_url = "#{GitHub.stafftools_url}#{stafftools_user_overview_path(user)}"
    # Disable rubocop because we want to use the login here for anything staff/stafftools adjacent
    request_denied(request, "log in as @#{user}", stafftools_url) # rubocop:disable GitHub/DoNotAllowLogin
  end

  private

  def request_accepted(grant, request_action, stafftools_url)
    @grant = grant
    @requested_by = @grant.request.requested_by
    @request_action = request_action
    @stafftools_url = stafftools_url

    mail(
      to: user_email(@requested_by),
      subject: "[GitHub] Your request to #{@request_action} has been accepted!",
      template_name: "request_accepted",
    )
  end

  def request_denied(request, request_action, stafftools_url)
    @request = request
    @request_action = request_action
    @stafftools_url = stafftools_url

    mail(
      to: user_email(@request.requested_by),
      subject: "[GitHub] Your request to #{@request_action} has been denied. :(",
      template_name: "request_denied",
    )
  end
end
