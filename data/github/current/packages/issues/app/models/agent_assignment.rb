# typed: true
# frozen_string_literal: true

class AgentAssignment < ApplicationRecord::Domain::IssuesPullRequests
  include Repositories::BelongsToRepository

  belongs_to_repository_via_domain relation_name: :source_repository, foreign_key: :repository_id, class_name: "Repository"
  alias_attribute :source_repository_id, :repository_id
  belongs_to :assignee, foreign_key: :assignee_id, class_name: "User" # rubocop:todo Rails/InverseOf
  belongs_to :assigner, foreign_key: :assigner_id, class_name: "User" # rubocop:todo Rails/InverseOf
  belongs_to_repository_via_domain relation_name: :target_repository, foreign_key: :target_repository_id, class_name: "Repository", optional: true
  belongs_to :target_owner, foreign_key: :target_owner_id, class_name: "User", optional: true # rubocop:todo Rails/InverseOf

  enum :source_type, { issue: 0 }, suffix: :source


  validates :source_type, presence: true
  validates :source_id, presence: true
  validates :assignee_id, presence: true
  validates :assigner_id, presence: true
  validates :source_repository, presence: true
  validates :task_id, uniqueness: { scope: :source_repository_id }, allow_nil: true

  validate :validate_source_exists, on: :create
  validate :validate_assignee_is_agent_bot, on: :create

  after_commit :notify_socket_subscribers, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  # Returns the source record based on source_type and source_id
  def source
    case source_type
    when "issue"
      Issue.find_by(id: source_id, repository_id: source_repository_id)
    end
  end

  def notify_socket_subscribers
    case source_type
    when "issue"
      notify_issue_socket_subscribers
    end
  end

  def notify_issue_socket_subscribers
    return unless (issue = source)

    data = {
      timestamp: Time.now.to_i,
      wait: default_live_updates_wait,
      reason: "agent assignment created for issue ##{issue.id}",
    }
    channel = GitHub::WebSocket::Channels.issue(issue)
    GitHub::WebSocket.notify_issue_channel(issue, channel, data)
    # We also need to alert graphql subscriptions that the issue has been updated so that we effectively refresh all
    # places where assignees are shown (and where we may also show assignment information)
    Platform::Schema.subscriptions.trigger(:issue_updated, { id: issue.global_relay_id }, object: { issue_metadata_updated: true })
  end

  private

  def validate_source_exists
    return if source_id.blank? || source_repository_id.blank? || source_type.blank?

    case source_type
    when "issue"
      unless Issue.where(id: source_id, repository_id: source_repository_id).exists?
        errors.add(:source_id, "does not reference a valid Issue")
      end
    else
      errors.add(:source_type, "is not a recognized source type")
    end
  end

  def validate_assignee_is_agent_bot
    return if assignee_id.blank?

    assignee_user = assignee
    unless assignee_user
      errors.add(:assignee_id, "does not reference a valid user")
      return
    end

    unless assignee_user.bot?
      errors.add(:assignee, "must be a bot")
      return
    end

    agentic_app = AgenticApp.agent_for_bot_id(assignee_user.id)
    unless agentic_app
      errors.add(:assignee, "must be a bot with an agent integration")
    end
  end
end
