# typed: strict
# frozen_string_literal: true

class SubIssueList < ApplicationRecord::Domain::IssuesPullRequests
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  belongs_to :issue, inverse_of: :sub_issue_list
  before_validation :set_repository_id, on: :create
  validates :repository_id, presence: true, on: :create

  sig { returns(SubIssueList) }
  def recalculate!
    return self unless issue = self.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    sub_issues = issue.sub_issues.to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    self.total = sub_issues.count
    self.completed = sub_issues.count { |sub_issue| sub_issue.closed? }
    self.save!

    issue.notify_sub_issues_summary_updated

    instrument_recalculation
    self
  end

  sig { override.returns(MemexProjectColumnValue::SubIssuesProgress) }
  memoize def memex_project_column_value
    MemexProjectColumnValue::SubIssuesProgress.new(
      total: total,
      completed: completed,
      percent_completed: percent_completed
    )
  end

  sig { returns(T::Hash[Symbol, Integer]) }
  def to_h
    {
      total: total,
      completed: completed,
      percent_completed: percent_completed
    }
  end

  sig { returns(Integer) }
  def percent_completed
    total.nonzero? ? (completed.to_f / total.to_f * 100).to_i : 0
  end

  sig { void }
  private def set_repository_id
    return unless issue = self.issue
    self.repository_id = issue.repository_id
  end

  sig { void }
  private def instrument_recalculation
    return unless issue = self.issue
    sub_issue_list = issue.sub_issue_list || { total: 0, completed: 0, percent_completed: 0 }
    GlobalInstrumenter.instrument("sub_issue.list.recalculate", {
      source_issue: issue,
      total: sub_issue_list[:total],
      completed: sub_issue_list[:completed],
      percent_completed: sub_issue_list[:percent_completed],
    })
  end
end
