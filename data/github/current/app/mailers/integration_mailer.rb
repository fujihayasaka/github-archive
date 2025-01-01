# typed: true
# frozen_string_literal: true

class IntegrationMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include GitHub::RouteHelpers

  self.mailer_name = "mailers/integration"

  layout "account/security", only: [
    :authorized,
  ]

  def authorized(authorization:)
    @view = Oauth::AuthorizeIntegrationView.new(authorization: authorization, application: authorization.application)
    @user = @view.user

    @application_description = description_for_application(@view.application)

    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] #{@application_description} has been added to your account",
      template_name: :authorized,
      categories: "account-security,new-oauth-authorization",
    )
  end

  def re_authorized(authorization:, previous_version:)
    view = Oauth::AuthorizeIntegrationView.new(
      authorization:    authorization,
      application:      authorization.application,
      previous_version: previous_version,
    )

    return unless view.permissions_added.any? || view.permissions_upgraded.any?

    @view = view
    @user = @view.user

    @application_description = description_for_application(@view.application)

    mail_to_primary_bcc_remaining_account_related_emails(
      subject: "[GitHub] #{@application_description} is using new permissions",
      template_name: :re_authorized,
      categories: "account-security,new-oauth-authorization",
    )
  end

  def updated_permissions(integration_installation, recipient: nil)
    @integration_installation = integration_installation
    @integration              = @integration_installation.integration
    @target                   = @integration_installation.target

    @path = gh_permissions_update_request_settings_installation_path(@integration_installation)

    options = {
      from:    github_noreply,
      to:      emails_for_admins(@target, [recipient]),
      subject: "[GitHub] #{@integration.name} is requesting updated permissions",
    }

    mail(options)
  end

  def updated_permissions_repo_adminable(integration_installation, recipient: nil)
    @integration_installation = integration_installation
    @integration              = @integration_installation.integration
    @target                   = @integration_installation.target

    @path = gh_edit_app_installation_permissions_path(@integration, @integration_installation, @target)

    options = {
      from:    github_noreply,
      to:      emails_for_admins(@target, [recipient]),
      subject: "[GitHub] #{@integration.name} is requesting updated permissions",
    }

    mail(options) do |format|
      format.html { render "updated_permissions" }
      format.text { render "updated_permissions" }
    end
  end

  def integration_installation_request(request)
    @requester = request.requester
    @integration = request.integration
    @target = request.target
    @url = gh_app_installation_permissions_url(@integration, @target, target_id: @target.id, request_id: request.id)

    options = {
      from: github_noreply,
      bcc:  admin_emails(@target),
      subject: "Request to install #{@integration.name} in #{@target.display_login}",
    }

    mail(options)
  end

  private

  def description_for_application(application)
    if application.github_owned?
      "A GitHub owned Application"
    else
      "A third-party GitHub Application"
    end
  end
end
