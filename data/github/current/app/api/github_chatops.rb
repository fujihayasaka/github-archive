# typed: true
# frozen_string_literal: true

class Api::GitHubChatops < Api::App
  include Api::App::ScheduledReminderHelpers

  def ms_teams?
    workspace_klass.to_s == "ReminderTeamsWorkspace"
  end

  ## Ensure only Ms Teams & Slack integration can access these apis
  before { deliver_error!(404) unless Apps::Privileged.capable?(:access_internal_reminders_api, app: current_integration) }

  ### CRUD APIs for personal scoped reminders

  # This API creates/updates personal reminder for an user for a particular organization
  put "/personal_schedule_reminders/:organization_id", operation_id: :internal, read_from_replicas: true do
    org = find_org!
    control_access :read_user_reminders,
      resource: org,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_schema("personal-reminder", "create-or-udpate-personal-reminder")

    with_write do
      begin
        status = create_update_personal_reminder_for_org(org, data)
        personal_reminder = get_personal_reminder_for_org org
        personal_reminder[:status] = status
        deliver_raw(personal_reminder)
      rescue ActiveRecord::ActiveRecordError => exception
        deliver_error! 400, message: exception
      end
    end
  end

  # This API lists down all the personal schedule reminders which are created for a user (across orgs)
  # example personal_schedule_reminders
  get "/personal_schedule_reminders", operation_id: :internal do
    control_access :read_user_reminders,
      resource: current_user,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_raw(get_personal_reminders_for_user)
  end

  # This API fetches the personal schedule reminders which are created for a user in a particular org
  # example personal_schedule_reminder/3
  get "/personal_schedule_reminders/:organization_id", operation_id: :internal do
    org = find_org!
    control_access :read_user_reminders,
      resource: org,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_raw(get_personal_reminder_for_org org)
  end

  # This API delete down the personal schedule reminders which are created for a user in a particular org
  # example personal_schedule_reminder/3
  delete "/personal_schedule_reminders/:organization_id", operation_id: :internal, read_from_replicas: true do
    org = find_org!
    control_access :read_user_reminders,
      resource: org,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    with_write do
      begin
        result = delete_personal_reminder_for_org org
        deliver_empty status: (result == true ? 204 : 404)
      rescue ActiveRecord::ActiveRecordError => exception
        deliver_error! 400, message: exception
      end
    end
  end

  ### CRUD APIs for org/team scoped reminders

  ## Get All reminders for an organization
  get "/schedule_reminders/:organization_id/reminders", operation_id: :internal do
    find_org!

    if FeatureFlag.vexi.enabled?(:scheduled_reminders_teams_parity, current_user, default: false) && ms_teams?
      control_access :read_user_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    else
      control_access :access_org_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    end

    deliver_raw(get_reminders params[:team_id])

  end

  ## GET all reminders for a client_id and channel_id combination, using query params client_id and channel_id
  get "/schedule_reminders/reminders", operation_id: :internal do
    if params["client_id"].blank? || params["channel_id"].blank?
      deliver_error! 422, message: "Both of client_id and channel_id are required to fetch reminders"
    end

    control_access :access_reminders_cross_org,
      resource: current_user,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    workspaces = workspace_klass.where("#{workspace_type_id_attribute}": params[:client_id])
    grouped_reminders = get_reminders_cross_org workspaces, params[:channel_id]
    enhanced_grouped_reminders = grouped_reminders.map do |org_id, org_reminders|
      {
        org_id: org_id,
        org_name: org_reminders[0][:org_name],
        reminders: org_reminders
      }
    end
    deliver_raw(enhanced_grouped_reminders)
  end

  ## GET a single reminder, using reminder_id for the current organization
  get "/schedule_reminders/:organization_id/reminder/:reminder_id", operation_id: :internal do
    find_org!
    if FeatureFlag.vexi.enabled?(:scheduled_reminders_teams_parity, current_user, default: false) && ms_teams?
      control_access :read_user_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    else
      control_access :access_org_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    end

    reminder = record_or_404 get_reminder(params[:reminder_id])

    deliver_raw(reminder.api_hash)

  end

  post "/schedule_reminders/:organization_id/reminders", operation_id: :internal, read_from_replicas: true do
    find_org!

    data = receive_with_schema("reminder", "create-reminder")

    if FeatureFlag.vexi.enabled?(:scheduled_reminders_teams_parity, current_user, default: false) && ms_teams?
      control_access :read_user_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    else
      control_access :access_org_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    end

    with_write do
      reminder = create_reminder_for_org(@current_org, data)
      if reminder.valid?
        deliver_raw(reminder.api_hash)
      else
        deliver_error! 422, message: reminder.errors.full_messages.join(",")
      end
    end
  end

  ## API to update org level reminder
  put "/schedule_reminders/:organization_id/reminder/:reminder_id", operation_id: :internal, read_from_replicas: true do
    find_org!

    data = receive_with_schema("reminder", "update-reminder")

    if FeatureFlag.vexi.enabled?(:scheduled_reminders_teams_parity, current_user, default: false) && ms_teams?
      control_access :read_user_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    else
      control_access :access_org_reminders,
          resource: @current_org,
          member: current_user,
          forbid: true,
          allow_integrations: false,
          allow_user_via_granular_actor: true
    end
    reminder = record_or_404 get_reminder(params[:reminder_id])

    with_write do
      updated_reminder = update_reminder_for_org(@current_org, reminder, data)
      case updated_reminder
      when Hash
        deliver_raw(updated_reminder)
      when String
        deliver_error! 422, message: updated_reminder
      end
    end
  end

  ## DELETE a reminder
  delete "/schedule_reminders/:organization_id/reminder/:reminder_id", operation_id: :internal, read_from_replicas: true do
    find_org!

    if FeatureFlag.vexi.enabled?(:scheduled_reminders_teams_parity, current_user, default: false) && ms_teams?
      control_access :read_user_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    else
      control_access :access_org_reminders,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    end

    reminder = record_or_404 get_reminder(params[:reminder_id])
    with_write do
      success = reminder.destroy
      if success
        deliver_raw({ status: "SUCCESS", message: "Reminder successfully deleted" })
      else
        deliver_error! 422, reminder.errors.full_messages.join(",")
      end
    end
  end



  ### CRUD APIs for reminder workpsace

  ## This api gets the reminder workspaces for an org for a particular integration app(MS Teams/Slack)
  get "/schedule_reminders/:organization_id/workspaces", operation_id: :internal do
    find_org!

    control_access :reader_reminder_workspace,
      resource: @current_org,
      member: current_user,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    reminder_slack_workspaces = workspace_klass.where(
      remindable: @current_org,
    )
    deliver_raw(
      reminder_slack_workspaces.map do |workspace|
        {
          workspace_id: workspace.id,
          name: workspace.name,
          "#{workspace_type_id_attribute}": workspace[workspace_type_id_attribute]
        }
      end
    )

  end

  ## This api creates or updates a workspace for an org
  put "/schedule_reminders/:organization_id/workspaces", operation_id: :internal, read_from_replicas: true do
    find_org!
    data = receive_with_schema("schedule-reminder-workspace", "create")

    ## For Ms Teams personal scoped chat concept of workspace id does not exist,
    ## This requires that we add hard coded data for only Ms Teams personal scope flow
    if Apps::Privileged.capable?(:scheduled_reminders_user_scoped_setup, app: current_integration) && data["is_user_scoped_setup"]
      data["client_name"] = "Microsoft Teams"
      data["client_id"] = ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID
    end
    if FeatureFlag.vexi.enabled?(:scheduled_reminders_teams_parity, current_user, default: false) && ms_teams?
      control_access :reader_reminder_workspace,
        resource: @current_org,
        member: current_user,
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    else
      control_access :modify_reminder_workspace,
        resource: @current_org,
        member: current_user,
        workspace: existing_workspace(data["client_id"]),
        forbid: true,
        allow_integrations: false,
        allow_user_via_granular_actor: true
    end

    if data["client_id"].blank? || data["client_name"].blank?
      deliver_error! 422, message: "Both of client_id and client_name are required to create a new workspace"
    end

    with_write do
      create_or_update_workspace_and_membership!(data["client_id"], data["client_name"])
      deliver_raw(workspace_klass.find_by(remindable: @current_org, "#{workspace_type_id_attribute}": data["client_id"]).as_json(dangerously_allow_all_keys: true))
    end

  end

  ## This api deletes a workspace for an org, the workspace id being the id of the workspace type
  delete "/schedule_reminders/:organization_id/workspace/:workspace_id", operation_id: :internal, read_from_replicas: true do
    find_org!

    reminder_slack_workspace = workspace_klass.where(
      remindable: @current_org,
      "#{workspace_type_id_attribute}": params[:workspace_id],
    ).first

    control_access :modify_reminder_workspace,
      resource: @current_org,
      member: current_user,
      workspace: reminder_slack_workspace,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    with_write do
      if !reminder_slack_workspace.nil?
        success = reminder_slack_workspace.destroy
        if success
          deliver_raw({ status: "SUCCESS", message: "Workspace successfully deleted" })
        else
          deliver_error! 422, message: reminder_slack_workspace.errors.full_messages.join(",")
        end
      else
        deliver_error! 404, message: "No Workspace found with workspace_id: #{params[:workspace_id]}"
      end
    end
  end

  ### Search APIs for reminders

  ## This API search the teams for a particular organization in MS teams. The logic is reused from Teams search api in Slack integration.
  get "/schedule_reminders/organizations/:organization_id/teams/search", operation_id: :internal do
    find_org!
    control_access :read_user_reminders,
      resource: @current_org,
      member: current_user,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    scope = @current_org.visible_teams_for(current_user).closed.limit(25)
    teams = Team.search_name_and_slug(query: params[:q], scope: scope).to_a

    deliver :team_hash, teams
  end

end
