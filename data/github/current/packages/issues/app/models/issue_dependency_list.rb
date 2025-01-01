# typed: strict
# frozen_string_literal: true

# Model representing the issue dependency lists.
class IssueDependencyList < ApplicationRecord::Domain::IssuesPullRequests
  # Includes aggregated count information about the number of blocking/blocked by relationships for an issue.
  class Summary < T::Struct
    # Number of open issues that block this issue
    const :blocked_by, Integer
    # Total number of issues that block this issue (open and closed)
    const :total_blocked_by, Integer
    # Number of open issues that this issue blocks
    const :blocking, Integer
    # Total number of issues that this issue blocks (open and closed)
    const :total_blocking, Integer

    # Returns an empty issue dependency summary (all counts set to zero).
    sig { returns(T.attached_class) }
    def self.empty
      new(
        blocked_by: 0,
        total_blocked_by: 0,
        blocking: 0,
        total_blocking: 0
      )
    end
  end

  belongs_to :issue, inverse_of: :issue_dependency_list
  before_validation :set_repository_id, on: :create
  validates :issue_id, uniqueness: true, presence: true

  sig { returns(IssueDependencyList) }
  def recalculate!
    return self unless issue = self.issue

    summary = issue.calculate_issue_dependency_summary
    self.blocked_by = summary.blocked_by
    self.total_blocked_by = summary.total_blocked_by
    self.blocking = summary.blocking
    self.total_blocking = summary.total_blocking

    self.save!

    issue.notify_issue_dependencies_summary_updated
    instrument_recalculation

    self
  end

  # Turns this record into a summary object that can be used in API responses or other contexts where we
  # only need the aggregated counts.
  sig { returns(Summary) }
  def to_summary
    Summary.new(
      blocked_by: self.blocked_by,
      total_blocked_by: self.total_blocked_by,
      blocking: self.blocking,
      total_blocking: self.total_blocking
    )
  end

  sig { void }
  private def set_repository_id
    return unless issue = self.issue
    self.repository_id = issue.repository_id
  end

  sig { void }
  private def instrument_recalculation
    return unless issue = self.issue

    GlobalInstrumenter.instrument("issue_dependency.list.recalculate", {
      issue: issue,
      repository_id: self.repository_id,
      blocked_by: self.blocked_by,
      blocking: self.blocking,
    })
  end
end
