# typed: true
# frozen_string_literal: true

class Reminders::EditView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :reminder, :slack_workspaces, :locked_to_team

  def title
    "Scheduled reminders - #{reminder.remindable.name} - Edit"
  end

  def heading
    if reminder.new_record?
      "New scheduled reminder"
    else
      "Scheduled reminder for #{reminder.slack_workspace&.name || "Slack"}"
    end
  end

  def slack_channel_default_error
    "Channel names cannot contain spaces, periods, special characters, or uppercase letters."
  end

  def slack_channel_id_or_name_default_error
    "When providing a channel name it cannot contain spaces, periods, special characters, or uppercase letters. When providing a channel ID it needs to follow a format similar to C1234567890"
  end

  def new_record?
    reminder.new_record?
  end

  def locked_to_team?
    locked_to_team.present?
  end

  def can_add_slack_workspace?
    locked_to_team.nil?
  end

  def selected_teams
    # We used `.order(name: :desc)` which forces a new database call to do the ordering.
    # This means that new records will always return [] for new records.
    # Existing records will return what's in the DB, not what's on the current instance of reminders. Instead, we must use `sort_by`.
    # This is especially important for validation issues where the reminder is not saved, but has changes on the teams attributes.
    reminder.teams.sort_by(&:name)
  end

  def organization
    reminder.remindable
  end

  def selected_days
    days = if new_record?
      ReminderDeliveryTime::WEEKDAYS.keys
    else
      reminder.days
    end
  end

  def days_text
    return "Weekdays" if new_record?
    reminder.delivery_days_text
  end

  # Get array of selected times. Defaults to ["9:00 AM"] for new records.
  #
  # @return [Array] List of time names (e.g., 9:00 AM).
  def selected_times
    if new_record?
      ["9:00 AM"]
    else
      reminder.times
    end
  end

  def ignore_after_approval_count_options
    {
      options: {
        1 => "Ignore with 1 or more approvals",
        2 => "Ignore with 2 or more approvals",
        3 => "Ignore with 3 or more approvals",
      },
      selected: reminder.ignore_after_approval_count,
    }
  end

  def default_ignore_after_approval_count?
    reminder.ignore_after_approval_count == 0
  end

  def needed_reviews_count_options
    {
      options: {
        0 => "After all review requests are fulfilled",
        1 => "After one review",
        2 => "After two reviews",
        3 => "After three reviews",
      },
      selected: reminder.needed_reviews,
    }
  end

  def selected_needed_reviews_option
    reminder.needed_reviews
  end

  # This is the option which is selected in the details-menu by default
  def selected_ignore_after_approval_option
    if default_ignore_after_approval_count?
      1
    else
      reminder.ignore_after_approval_count
    end
  end

  def repositories_target_selected?(target)
    case target
    when :selected
      reminder.tracked_repositories.any?
    when :all
      reminder.tracked_repositories.empty?
    end
  end

  def add_by_channel_id_or_name?
    reminder.add_by_channel_id_or_name?
  end
end
