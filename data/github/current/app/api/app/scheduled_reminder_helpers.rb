# typed: false
# frozen_string_literal: true

module Api::App::ScheduledReminderHelpers
  private

  def find_personal_reminder(org_id)
    organizations = current_user.organizations.find_by_id(org_id)
    PersonalReminder.includes(:delivery_times).find_by(user: current_user, remindable: organizations)
  end

  def get_personal_reminder_for_org(org_id)
    personal_reminder = find_personal_reminder(org_id)
    if personal_reminder
      enhanced_personal_reminder = personal_reminder.api_hash
      enhanced_personal_reminder[:created_at] = personal_reminder.created_at
      enhanced_personal_reminder
    end
  end

  def create_update_personal_reminder_for_org(org_id, chatops_personal_reminder)
    ReminderSlackWorkspaceMembership.create_or_update_membership(
      user_id: current_user.id,
      reminder_slack_workspace_id: chatops_personal_reminder["reminder_slack_workspace_id"],
    )

    existing_personal_reminder = find_personal_reminder(org_id)
    if existing_personal_reminder
      update_personal_reminder_for_org(existing_personal_reminder, chatops_personal_reminder)
      :updated
    else
      create_personal_reminder_for_org(org_id, chatops_personal_reminder)
      :created
    end
  end

  def create_personal_reminder_for_org(org_id, chatops_personal_reminder)
    organizations = current_user.organizations.find_by_id(org_id)
    PersonalReminder.create!(user: current_user, remindable: organizations) do |reminder|
      reminder.include_review_requests = chatops_personal_reminder["include_review_requests"]
      reminder.include_team_review_requests = chatops_personal_reminder["include_team_review_requests"]
      reminder.reminder_slack_workspace_id = chatops_personal_reminder["reminder_slack_workspace_id"]
      reminder.time_zone_name = chatops_personal_reminder["time_zone_name"]
      reminder.delivery_times_attributes = build_delivery_times_attributes(chatops_personal_reminder["delivery_times"])
      reminder.event_subscriptions_attributes = chatops_personal_reminder["reminder_event_subscriptions"]
    end
  end

  def update_personal_reminder_for_org(personal_reminder, chatops_personal_reminder)
    personal_reminder.update!(include_review_requests: chatops_personal_reminder["include_review_requests"],
      include_team_review_requests: chatops_personal_reminder["include_team_review_requests"],
      reminder_slack_workspace_id: chatops_personal_reminder["reminder_slack_workspace_id"],
      time_zone_name: chatops_personal_reminder["time_zone_name"],
      delivery_times_attributes: build_delivery_times_attributes(chatops_personal_reminder["delivery_times"]),
      event_subscriptions_attributes: chatops_personal_reminder["reminder_event_subscriptions"])
    personal_reminder
  end

  def delete_personal_reminder_for_org(org_id)
    personal_reminder = find_personal_reminder(org_id)
    # when reminder does not exist and delete is called return false
    return false unless personal_reminder.present?

    personal_reminder.destroy!
    true
  end

  def get_personal_reminders_for_user
    hydreated_reminders = Array.new
    organizations = current_user.organizations.order(:login).to_a
    personal_reminders = PersonalReminder.where(user: current_user, remindable: organizations).includes(:delivery_times)
    GitHub::PrefillAssociations.prefill_associations(personal_reminders, { remindable: :slack_workspace })
    personal_reminders_by_remindable = personal_reminders.index_by(&:remindable)

    if organizations.any?
      organizations.map do |organization|
        if personal_reminders_by_remindable[organization]
          enhanced_personal_reminder = personal_reminders_by_remindable[organization].api_hash
          enhanced_personal_reminder[:org_id] = organization.id
          enhanced_personal_reminder[:org_name] = organization.login_for_api
          enhanced_personal_reminder[:created_at] = personal_reminders_by_remindable[organization].created_at
          hydreated_reminders.push(enhanced_personal_reminder)
        end
      end
    end
    hydreated_reminders
  end

  def build_delivery_times_attributes(delivery_time_params)
    delivery_time_params ||= {}
    times = Array(delivery_time_params["times"]).uniq.select(&:present?)
    days = Array(delivery_time_params["days"]).uniq.select(&:present?)

    days.product(times).map do |(day, time)|
      { day: day, time: time }.stringify_keys
    end
  end

  def get_reminders(team_id)
    if team_id.nil?
      reminders = Reminder.includes(:team_memberships, :delivery_times, :repository_links).where(remindable: @current_org)
    else
      reminder_ids = ReminderTeamMembership.where(team_id: team_id).pluck(:reminder_id)
      reminders = Reminder.tied_to_single_team.preload(:team_memberships, :delivery_times, :repository_links).where(remindable: @current_org, reminders: {  id: reminder_ids })
    end
    GitHub::PrefillAssociations.prefill_associations(reminders, { remindable: :slack_workspace })
    reminders.map do |reminder|
      reminder.api_hash
    end
  end

  def get_reminders_cross_org(workspaces, channel_id)
    reminders = Reminder.includes(:team_memberships, :delivery_times, :repository_links).where(slack_workspace: workspaces, slack_channel_id: channel_id)
    GitHub::PrefillAssociations.prefill_associations(reminders, { remindable: :slack_workspace })
    reminders.map(&:api_hash).group_by { |reminder| reminder[:org_id] }
  end

  def get_reminder(reminder_id)
    Reminder.includes(:team_memberships, :delivery_times, :repository_links).find_by(id: reminder_id, remindable: @current_org)
  end

  def create_reminder_for_org(org, chatops_reminder)
    reminder = Reminder.new(remindable: org, user: current_user)
    reminder.assign_attributes(create_reminder_params(org, chatops_reminder))
    reminder.save
    ## Need to reload delivery times as the data could have come unordered, reloading orders the data
    ## which fixes the reminder text created to reflect correct values
    reminder.delivery_times.reload
    reminder
  end

  def update_reminder_for_org(org, reminder, chatops_reminder)
    # We want this next block in a DB transaction as we manipulate the associated has_many collections when we call `assign_attributes`. When we do this, those objects
    # are automatically deleted (like `team_memberships`). In the case that validation fails after/during the assignment, we need to make sure those deletes are rolled back. To accomplish this, a DB txn
    # is used. If we are not valid (has errors), then we raise `ActiveRecord::Rollback` to cause the deleted records to be rolled back.
    transaction_success = reminder.transaction do
      reminder.assign_attributes(create_reminder_params(org, chatops_reminder))
      raise ActiveRecord::Rollback unless reminder.valid?
      reminder.save
    end
    if transaction_success
      ## Need to reload delivery times as the data could have come unordered, reloading orders the data
      ## which fixes the reminder text created to reflect correct values
      reminder.delivery_times.reload
      reminder.api_hash
    else
      "There was an error: #{reminder.errors.full_messages.to_sentence}"
    end
  end

  def create_reminder_params(org, chatops_reminder)
    if team_names = chatops_reminder.delete("teams")
      team_ids = Team.where(slug: team_names, organization: org).pluck(:id)
      chatops_reminder["team_ids"] = team_ids
    end
    if repo_names = chatops_reminder.delete("repos")
      repo_ids = Repository.where(name: repo_names, organization: org).pluck(:id)
      chatops_reminder["tracked_repository_ids"] = repo_ids
    else
      chatops_reminder["tracked_repository_ids"] = []
    end
    if delivery_times = chatops_reminder.delete("delivery_times")
      chatops_reminder["delivery_times_attributes"] = build_delivery_times_attributes(delivery_times)
    end
    if channel_name = chatops_reminder.delete("channel_name")
      chatops_reminder["slack_channel"] = channel_name
    end
    if channel_id = chatops_reminder.delete("channel_id")
      chatops_reminder["slack_channel_id"] = channel_id
    end
    if reminder_workspace_id = chatops_reminder.delete("reminder_workspace_id")
      chatops_reminder["reminder_slack_workspace_id"] = reminder_workspace_id
    end
    if chatops_reminder["user_id"] != current_user.id
      chatops_reminder["user_id"] = current_user.id
    end
    chatops_reminder
  end

  def workspace_klass
    @workspace_klass ||= Apps::Internal.property(
      :scheduled_reminders_workspace_class,
      app: current_integration
    )&.constantize
  rescue NameError
    nil
  end

  def workspace_type_id_attribute
    @workspaces_type_id_attribute ||= Apps::Internal.property(
      :scheduled_reminders_workspace_type_id_attribute,
      app: current_integration
    )
  end

  def existing_workspace(client_id)
    return nil unless workspace_klass.present? && workspace_type_id_attribute.present?

    workspace = workspace_klass.where(
      "#{workspace_type_id_attribute}": client_id,
      remindable: @current_org,
    ).first
    ## The following code adds a workspace entry for Ms Teams personal scope.
    ## For Ms Teams personal scoped chat concept of workspace id does not exist,
    ## hence we want the entry for personal scoped workspace to always be present for Ms Teams
    if client_id == ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID && workspace.nil?
      workspace = workspace_klass.create_or_update_workspace(
        name: "Microsoft Teams",
        remindable: @current_org,
        "#{workspace_type_id_attribute}": client_id
      )
    end
    workspace
  end

  def create_or_update_workspace_and_membership!(client_id, client_name)
    return unless workspace_klass && workspace_type_id_attribute

    workspace_klass.transaction do
      workspace = workspace_klass.create_or_update_workspace(
        name: client_name,
        remindable: @current_org,
        "#{workspace_type_id_attribute}": client_id
      )

      ReminderSlackWorkspaceMembership.create_or_update_membership(
        user_id: current_user.id,
        reminder_slack_workspace_id: workspace.id,
      )
    end
  end
end
