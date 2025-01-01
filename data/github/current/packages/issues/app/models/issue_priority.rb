# typed: true
# frozen_string_literal: true

class IssuePriority < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Prioritizable

  belongs_to :issue, touch: true
  belongs_to :milestone, touch: true, inverse_of: :issue_priorities

  before_validation :set_repository_id, on: :create

  validates :issue, :milestone, presence: true
  validates :priority,
    presence: true,
    uniqueness: {
      scope: :milestone_id },
    numericality: {
      less_than_or_equal_to: MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0 }
  validates :repository_id, presence: true, on: :create

  prioritizable_by subject: :issue, context: :milestone
  # This is okay since we are queuing the job in the after_commit callback
  after_commit :synchronize_search_index, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :by_milestone, ->(milestone_id) { where(milestone_id: milestone_id) }

  private def set_repository_id
    self.repository_id = issue&.repository_id
  end

  def synchronize_search_index
    issue&.synchronize_search_index
  end

  def self.should_synchronize_search_index?
    true
  end
end
