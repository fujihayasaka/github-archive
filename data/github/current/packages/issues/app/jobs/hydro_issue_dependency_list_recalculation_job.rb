# typed: true
# frozen_string_literal: true

class HydroIssueDependencyListRecalculationJob < HydroMessageJob
  queue_as :hydro_issue_dependency_list_recalculation
  retry_on_dirty_exit

  sig { void }
  def perform
    if topic.match(/github\.v1\.(BlockedByAdd|BlockedByRemove)$/)
      source_issue_id = message.dig(:source_issue, :id)
      target_issue_id = message.dig(:target_issue, :id)

      source_issue = Issue.find_by(id: source_issue_id)
      target_issue = Issue.find_by(id: target_issue_id)

      with_write do
        source_issue.recalculate_issue_dependency_list! if source_issue
        target_issue.recalculate_issue_dependency_list! if target_issue
      end
    # IssueReopen and IssueClose message topics use the legacy format, e.g. `cp1-iad.ingest.github.v1.IssueReopen`.
    elsif topic.match(/github\.v1\.(IssueReopen|IssueClose)$/)
      issue_id = message.dig(:issue, :id)

      blocked_issue_ids = IssueDependency.where(target_issue_id: issue_id, dependency_type: :blocked_by).map(&:source_issue_id)
      blocking_issue_ids = IssueDependency.where(source_issue_id: issue_id, dependency_type: :blocked_by).map(&:target_issue_id)

      blocked_and_blocking_issues = Issue.where(id: (blocked_issue_ids + blocking_issue_ids))

      blocked_and_blocking_issues.each do |issue|
        with_write { issue.recalculate_issue_dependency_list! }
      end.each(&:synchronize_search_index) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
