# typed: true
# frozen_string_literal: true

class Hook::Event::ReminderEvent < Hook::Event
  supports_targets Integration
  description "Pull request reminders sent"
  event_attr :action, :event_at, :reminder_id, :repository_id, required: true
  event_attr :actor_id, :pull_request_ids, :reminder_event_context, :reminder_event_type, :personal, :pull_request_ids_for_author

  TYPE_REALTIME  = "realtime"
  TYPE_SCHEDULED = "scheduled"
  TYPE_DELETED = "deleted"

  def self.queue(event_at:, pull_request_ids:, pull_request_ids_for_author: [], reminder:, repository_id:, actor: nil, event_context: nil, event_type: nil)
    type = event_type.present? ? TYPE_REALTIME : TYPE_SCHEDULED
    personal = reminder.is_a?(PersonalReminder)
    event_type_db = ReminderEventSubscription.event_types[event_type] if event_type.present?
    log_params = {
      "gh.webhook.event_at" => event_at,
      "gh.webhook.event_type" => event_type || "",
      "gh.webhook.event_type_db" => event_type_db || "",
      "gh.scheduled_reminders.is_personal" => personal,
      "gh.scheduled_reminders.pull_request_ids" => pull_request_ids,
      "gh.scheduled_reminders.pull_request_ids_for_author" => pull_request_ids_for_author,
      "gh.scheduled_reminders.remindable.id" => reminder.remindable_id,
      "gh.scheduled_reminders.remindable.login" => reminder.remindable.login,
      "gh.scheduled_reminders.remindable.type" => reminder.remindable_type,
      "gh.scheduled_reminders.reminder.id" => reminder.id,
      "gh.scheduled_reminders.slack_workspace.id" => reminder.slack_workspace.slack_id,
      "gh.scheduled_reminders.reminder_event_type" => type,
      "gh.repo.id" => repository_id
    }
    if actor
      log_params["gh.actor.id"] = actor.id
      log_params["gh.actor.login"] = actor.login
    end

    if personal
      log_params["gh.user.id"] = reminder.user_id
      log_params["gh.user.login"] = T.must(reminder.user).login
    end

    GitHub::logger.info(log_params)

    super(
      action: type,
      actor_id: actor&.id,
      event_at: event_at,
      personal: personal,
      pull_request_ids: pull_request_ids,
      pull_request_ids_for_author: pull_request_ids_for_author,
      reminder_event_context: event_context,
      reminder_event_type: event_type,
      reminder_id: reminder.id,
      repository_id: repository_id
    )
  end

  def actor
    @actor ||= User.find_by(id: actor_id) if actor_id
  end

  def reminder_event_context
    @reminder_event_context ||= (attributes[:reminder_event_context] || {}).with_indifferent_access
  end

  def reminder
    @reminder ||= begin
      klass = personal ? PersonalReminder : Reminder
      klass.includes(:remindable).find(reminder_id)
    end
  end

  def target_organization
    @target_organization ||= reminder.remindable
  end

  # ActiveRecord::RecordNotFound errors end up getting retried indefinitely to avoid race condition errors
  # So we allow target_repository to be nillable and drop it in deliverable?
  #
  # Hook::Event will also drop this when target_repository is nil since event_type (reminder)
  # is a repository event type (under Pull Requests). See app/models/integration/events.rb
  #
  # However if we raise an error, we won't be able to gracefully drop it.
  def target_repository
    @target_repository ||= target_organization.org_repositories.find_by(id: repository_id)
  end

  def pull_requests
    # pull_requests.repository_id is nullable in the database
    # and as of 2019-11-06 we have 98 pull request records with a NULL repository_id
    #
    # Without an explicit return this would generate: WHERE `pull_requests`.`repository_id` IS NULL and query them
    @pull_requests ||= target_repository.nil? ? [] : PullRequest.for_repository(target_repository).where(id: pull_request_ids)
  end

  def pull_requests_for_author
    @pull_requests_for_author ||= target_repository.nil? ? [] : PullRequest.for_repository(target_repository).where(id: pull_request_ids_for_author)
  end

  # actor_id will be blank for batched/scheduled reminders and that's valid
  # actor_id only comes through with realtime reminders
  def deliverable?
    return true if action == TYPE_DELETED
    return false if target_repository.nil?
    return false if pull_requests.empty? && pull_requests_for_author.empty?
    return true if actor_id.blank?

    actor.present?
  end
end
