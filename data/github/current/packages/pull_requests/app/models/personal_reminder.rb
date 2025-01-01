# typed: true
# frozen_string_literal: true

class PersonalReminder < ApplicationRecord::Collab
  include ReminderScheduling
  include ReminderEvents
  include GitHub::Validations
  include GitHub::IFlipperActor
  include GitHub::VexiActor

  # rubocop:todo Rails/InverseOf
  belongs_to :slack_workspace, -> (reminder) { for_remindable(reminder.remindable) },
    class_name: "ReminderClientWorkspace", foreign_key: "reminder_slack_workspace_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :remindable, polymorphic: true
  belongs_to :user

  validates :slack_workspace, presence: true
  validates :remindable, presence: true
  validates :user, presence: true
  validate :check_slack_workspace
  validates :time_zone_name, unicode3: true
  scope :for_remindable, -> (remindable) { where(remindable: remindable) }

  scope :order_by_workspace, -> {
    joins("JOIN reminder_slack_workspaces ON reminder_slack_workspace_id = reminder_slack_workspaces.id")
    .order("reminder_slack_workspaces.name ASC, personal_reminders.id ASC")
  }

  def self.listener_ids_for(remindable, event_type:)
    for_remindable(remindable).for_event_type(event_type).pluck(:user_id)
  end

  def include_approved?
    ignore_after_approval_count.to_i < 1
  end

  def authorized_client_workspaces
    slack_workspace_memberships = ReminderSlackWorkspaceMembership.where(user: user)
    slack_workspace_ids = slack_workspace_memberships.pluck(:reminder_slack_workspace_id)
    ReminderClientWorkspace.where(remindable: remindable, id: slack_workspace_ids)
  end

  def check_slack_workspace
    return if slack_workspace.nil?

    if !authorized_client_workspaces.include?(slack_workspace)
      self.slack_workspace = nil
      self.errors.add(:slack_workspace, "can't be blank")
    end
  end

  def filtered_pull_requests
    PersonalReminderPullRequestFilter.batch_size = 500
    PersonalReminderPullRequestFilter.run(self)
  ensure
    PersonalReminderPullRequestFilter.reset_batch_size
  end

  def subscribed_to_events?
    event_types.present?
  end

  def reset_memoized_attributes
    @supports_private_repos = nil
  end

  def supports_private_repos?
    return false if remindable.nil?
    @supports_private_repos ||= remindable.plan_supports?(:reminders, visibility: "private", fallback_to_free: false)
  end

  def accessible_repository_ids
    org_repos = if supports_private_repos?
      remindable.repository_ids
    else
      remindable.repositories.public_scope.pluck(:id)
    end
    user&.associated_repository_ids(repository_ids: org_repos) || []
  end

  def permitted_to_repository_id?(repository_id)
    accessible_repository_ids.include?(repository_id)
  end

  def has_valid_associations?
    remindable.present? && user.present?
  end

  def ms_teams?
    slack_workspace&.type == "ReminderTeamsWorkspace"
  end

  def api_hash
    reminder_event_subscriptions = event_subscriptions.map do |event_subscription|
      {
        event_type: event_subscription.event_type,
        options: event_subscription.options
      }
    end
    {
      delivery_times: serialize_delivery_times,
      id: id,
      reminder_event_subscriptions: reminder_event_subscriptions,
      time_zone_name: time_zone_name,
      client_type: slack_workspace&.type,
      workspace_id: slack_workspace&.slack_id,
      workspace_name: slack_workspace&.name,
      reminder_text: delivery_times_text,
      include_review_requests: include_review_requests,
      include_team_review_requests: include_team_review_requests,
      supports_private_repos: supports_private_repos?,
      org_name: remindable.login_for_api,
      org_id: remindable_id
    }
  end

  def merge_conflict_sunset?
    FeatureFlag.vexi.enabled?(:merge_conflicts_reminder_sunset, user, default: false)
  end

  # Use this in feature flag checks when #user is nil
  def flipper_id
    "PersonalReminder:#{id}"
  end

  def vexi_id
    flipper_id
  end

  # Hash of memoized custom gates used for feature flag checks in lib/feature_flags_common/custom_gates.rb
  def memoized_custom_gates
    @memoized_custom_gates ||= {}
  end
end
