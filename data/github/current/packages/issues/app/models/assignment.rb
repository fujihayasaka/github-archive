# typed: true
# frozen_string_literal: true

class Assignment < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :issue
  belongs_to :assignee, foreign_key: :assignee_id, class_name: "User" # rubocop:todo Rails/InverseOf

  validates :issue, :assignee, presence: true
  validates :assignee_id, uniqueness: { scope: [:issue_id] }
  validate  :ensure_assignee_is_a_collaborator, unless: :skip_ensure_assignee_is_a_collaborator
  validates :repository_id, presence: true, on: :create
  attr_accessor :skip_ensure_assignee_is_a_collaborator

  before_validation :set_repository_id, on: :create
  after_commit :trigger_assigned_event, on: :create, unless: :skip_trigger_assigned_event # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  attr_accessor :skip_trigger_assigned_event

  after_commit :trigger_unassigned_event, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :for_assignee,  -> (assignee) { where(assignee_id: assignee.id) }
  scope :for_assignees, -> (assignees) { where(assignee_id: assignees.map(&:id)).by_age }
  scope :by_age, -> { order("assignments.created_at ASC") }

  delegate :repository, to: :issue

  def trigger_assigned_event
    T.must(issue).trigger_assigned_event(assignee)
  end

  # Only trigger an unassigned event if the issue is still around.
  # We don't want this to fire when the assignment is being destroyed
  # as a result of an issue being destroyed.
  def trigger_unassigned_event
    return unless issue.present? && assignee.present?
    T.must(issue).trigger_unassigned_event(assignee)
  end

  def ensure_assignee_is_a_collaborator
    return if T.must(assignee).ghost?

    unless T.must(issue).assignable_to?(assignee)
      errors.add :assignee, "must be a collaborator"
    end
  end

  private

  def set_repository_id
    self.repository_id = issue&.repository_id
  end
end
