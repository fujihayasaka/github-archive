# typed: true
# frozen_string_literal: true
class ReminderSlackWorkspacesController < ApplicationController

  before_action :login_required
  before_action :organization

  # This is necessary to send queries to a writable MySQL server since this is a GET route
  around_action :select_write_database, only: :callback

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:callback]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:callback], optional: true

  def authorize # rubocop:todo GitHub/UseRestfulActions
    referring_path = if params[:personal]
      personal_reminders_path
    else
      org_reminders_path(organization)
    end

    connector = ReminderSlackWorkspaceConnector.new(user: current_user, organization: organization)
    begin
      authorization_url = connector.authorization_url(
        referring_path: referring_path,
        redirect_url: callback_reminder_slack_workspace_url(organization),
      )
    rescue ReminderSlackWorkspaceConnector::IntegrationMissingError => e
      help_url = "https://github.com/integrations/slack/blob/master/README.md"
      flash[:error] = "#{e.message}. Learn more at #{help_url}"
    end

    GitHub.dogstats.increment("reminders.slack_authorize", tags: dogstats_request_tags + ["success:true"])

    render "reminders/slack_meta_redirect", locals: { redirect_url: authorization_url }, layout: "layouts/redirect"
  end

  def callback # rubocop:todo GitHub/UseRestfulActions
    workspace_jwt = params[:workspace].to_s

    if workspace_jwt.blank?
      render_404
      return
    end

    connector = ReminderSlackWorkspaceConnector.new(user: current_user, organization: organization)

    begin
      connector.connect(workspace_jwt)
      GitHub.dogstats.increment("reminders.slack_callback", tags: dogstats_request_tags + ["success:true"])
      flash[:notice] = "Connected Slack workspace #{connector.workspace.name}"
    rescue ReminderSlackWorkspaceConnector::Error => e
      GitHub.dogstats.increment("reminders.slack_callback", tags: dogstats_request_tags + ["error:#{e.code}", "success:false"])
      reminder_docs_url = "https://github.com/integrations/slack/blob/master/README.md#enterprise-grid"
      flash[:error] =
        if e.is_a?(ReminderSlackWorkspaceConnector::InsufficientPermissionsError)
          "Sorry, only organization owners can connect new Slack workspaces"
        elsif e.is_a?(ReminderSlackWorkspaceConnector::SelectedEnterpriseInRemindersError)
          "Could not add #{connector.enterprise_name}. Please pick a Slack workspace. Learn more at #{reminder_docs_url}."
        elsif e.is_a?(ReminderSlackWorkspaceConnector::SlackIntegrationError)
          GlobalInstrumenter.instrument("user.reminders.integration_error",
            actor: current_user,
            error: e.message,
            organization: organization,
          )
          e.message
        else
          "We had trouble verifying your Slack authentication. Please try again."
        end
    end

    safe_redirect_to(connector.referring_path || org_reminders_path(organization))
  end

  private

  # covered by login required and EMU visibility policy
  # don't want to enforce the policy because POSTs 404 instead of redirect and we need to redirect
  def tenant_verification_enforceable
    :no
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    organization
  end

  def organization
    return unless logged_in?
    @organization ||= current_user.organizations.find_by_login!(params[:organization_id])
  end
end
