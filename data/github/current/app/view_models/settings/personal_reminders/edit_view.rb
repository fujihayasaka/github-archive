# typed: true
# frozen_string_literal: true
class Settings::PersonalReminders::EditView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :personal_reminder
  attr_reader :available_chat_clients
  attr_reader :client_param

  def title
    "Scheduled reminders - #{personal_reminder.remindable.name} - Edit"
  end

  def heading
    if personal_reminder.new_record?
      "New scheduled reminder"
    else
      "Scheduled reminder for #{personal_reminder.remindable.display_login}"
    end
  end

  def form_url
    urls.personal_reminder_path(personal_reminder.remindable.display_login)
  end

  def new_record?
    ## Current spec is to ignore if a personal_reminder is already created for Ms Teams Client.
    ## i.e. customer should not even know that something else was configured.
    ## hence the added `is_ms_teams?` check
    personal_reminder.new_record? || personal_reminder.ms_teams?
  end

  def organization
    personal_reminder.remindable
  end

  def client_workspaces
    workspaces = personal_reminder.authorized_client_workspaces
    ## Add feature flag based on which it will either call ReminderClientWorkspace or ReminderSlackWorkspace
    ## Basically until all code is complete with all possible scenarios we will use this flag to ensure it's turned off for all users
    if GitHub.flipper[:scheduled_reminders_ms_teams].enabled?(personal_reminder.remindable)
      workspaces
    else
      workspaces.where(type: ReminderSlackWorkspace)
    end
  end

  def selected_workspace_for(client)
    personal_reminder.slack_workspace if personal_reminder.slack_workspace&.type == client.name
  end

  def selected_chat_client
    if client_param == :ReminderTeamsWorkspace.to_s
      ReminderTeamsWorkspace
    elsif client_param == :ReminderSlackWorkspace.to_s
      ReminderSlackWorkspace
    else
      personal_reminder.slack_workspace&.class
    end
  end

  def selected_days
    days = if new_record?
      ReminderDeliveryTime::WEEKDAYS.keys
    else
      personal_reminder.days
    end
  end

  def days_text
    return "Weekdays" if new_record?
    personal_reminder.delivery_days_text
  end

  # Get array of selected times. Defaults to ["9:00 AM"] for new records.
  #
  # @return [Array] List of time names (e.g., 9:00 AM).
  def selected_times
    if new_record?
      ["9:00 AM"]
    else
      personal_reminder.times
    end
  end

  def event_types
    {
      review_request: "You are assigned a review",
      team_review_request: "Your team is assigned a review",
      review_submission: "Your PR is approved or has changes requested",
      assignment: "You are made an assignee",
      comment: "Someone comments on your PR",
      comment_reply: "Someone comments in a thread you're in",
      mention: "You are mentioned in a comment",
      pull_request_merged: "Someone merges your pull request",
      merge_conflict: "Your PR has merge conflicts",
      check_failure: "Your PR has failed CI checks",
    }
  end

  def selected_event_types
    if personal_reminder.subscribed_to_events?
      personal_reminder.event_types
    else
      %w[review_request team_review_request review_submission]
    end
  end

  def ignore_after_approval_count_options
    [
      {
        "Include approved pull requests" => 0,
        "Ignore with 1 or more approvals" => 1,
        "Ignore with 2 or more approvals" => 2,
        "Ignore with 3 or more approvals" => 3,
      },
      personal_reminder.ignore_after_approval_count,
    ]
  end

  def real_time_options(event_type)
    event_subscriptions.find { |sub| sub.event_type == event_type }&.options
  end

  def real_time_selected?(event_type)
    personal_reminder.event_types.include?(event_type)
  end

  def real_time_options_placeholder(event_type)
    {
      check_failure: "Comma-separated list of check names",
    }[event_type.to_sym] || ""
  end

  def event_type_permits_option?(event_type)
    ReminderEventSubscription::EVENT_TYPES_PERMITTING_OPTIONS.include?(event_type.to_sym)
  end

  def event_subscriptions
    @event_subscriptions ||= personal_reminder.event_subscriptions
  end
end
