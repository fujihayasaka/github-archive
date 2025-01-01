# typed: true
# frozen_string_literal: true

# This job queues subsequent jobs to update ES documents for
# - all issues in a given repo
# - all related parent issues and sub-issues in other repos (sub-issue relations can be cross-repo)
# in order to get updated `parent_issue` and `sub_issue` values in the issues search index.
#
# Triggered by the following events:
# - github.repositories.v1.Renamed
# - github.repositories.v1.Transferred
class HydroReindexSubIssuesJob < Repositories::RepositoryHydroMessageJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :hydro_reindex_sub_issues

  sig { void }
  def perform
    return if repository.nil?
    return unless repository.has_issues?

    # Bulk re-index all issues in the given repo
    Search.add_to_search_index("bulk_issues", repository.id, "purge" => true)

    # Get issue ids for all issues in repo
    issue_ids = Issue.where(repository_id: repository.id).pluck(:id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return if issue_ids.empty?

    # Get all sub-issue relations for the given issues
    related_sub_issues = SubIssue
      .where(source_issue_id: issue_ids)
      .or(SubIssue.where(target_issue_id: issue_ids))
      .pluck(:source_issue_id, :target_issue_id)
    return if related_sub_issues.empty?

    # Get ids of all parents and sub-issues not in the repo
    sub_issue_ids_to_update = related_sub_issues
      .flatten
      .uniq
      .filter { |id| !issue_ids.include?(id) }
    return if sub_issue_ids_to_update.empty?

    # Update search index for all parents and sub-issues not in the repo
    issues_to_sync = Issue.where(id: sub_issue_ids_to_update)
    return if issues_to_sync.empty? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    issues_to_sync.each(&:synchronize_search_index) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
