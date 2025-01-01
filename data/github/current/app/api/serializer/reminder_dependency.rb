# typed: true
# frozen_string_literal: true

module Api::Serializer::ReminderDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer::IssuesDependency }

  def reminder_hash(reminder, options = {})
    return nil unless reminder

    delivery_times = reminder.delivery_times.map do |time|
      { day: time.day, time: time.time }
    end

    payload = {
      delivery_times: delivery_times,
      id: reminder.id,
      node_id: global_id_for(reminder, options),
      realtime_events: reminder.event_subscriptions.map(&:event_type).sort,
      time_zone_name: reminder.time_zone_name,
      client_type: reminder.slack_workspace.type,
      workspace_id: reminder.slack_workspace.slack_id,
      created_at: time(reminder.created_at),
      updated_at: time(reminder.updated_at),
    }

    remindable_param = reminder.remindable.to_param

    case reminder
    when Reminder
      reminder_url = if reminder.teams.count == 1
        team = reminder.teams.first
        html_url("/orgs/#{remindable_param}/teams/#{team.to_param}/settings/reminders/#{reminder.id}")
      else
        html_url("/organizations/#{remindable_param}/settings/reminders/#{reminder.id}")
      end
      payload.merge(
        channel_id: (reminder.slack_channel_id || reminder.slack_channel),
        html_url: reminder_url,
        ignore_after_approval_count: reminder.ignore_after_approval_count,
        ignore_draft_prs: reminder.ignore_draft_prs,
        require_review_request: reminder.require_review_request,
        settings: reminder.settings
      )
    when PersonalReminder
      payload.merge(
        html_url: html_url("/settings/reminders/#{remindable_param}"),
        recipient: simple_user_hash(reminder.user, options),
      )
    end
  end

  def reminder_context_hash(context, options = {})
    return {} if options[:event_type].nil?

    context = context.merge(event: options[:event_type])
    case context[:event]
    when "pull_request_labeled"
      label_id = context[:label_id]
      label = options[:repository].labels.find_by(id: label_id)
      if label
        context[:label] = label_hash(label, content_options(options))
        context.delete(:label_id)
      end
    end
    context
  end
end
