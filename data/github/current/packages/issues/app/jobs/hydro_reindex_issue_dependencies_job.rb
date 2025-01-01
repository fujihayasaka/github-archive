# typed: true
# frozen_string_literal: true

# This job queues subsequent jobs to update ES documents for
# - all issues in a given repo
# - all related issue dependencies in other repos (issue dependencies can be cross-repo)
# in order to get updated `blocked_by` and `blocking` values in the issues search index.
# - all related issue dependencies in other orgs (issue dependencies can be cross-org)
#
# Triggered by the following events:
# - github.repositories.v1.Renamed
# - github.repositories.v1.Transferred
# - github.v1.AccountRename

class HydroReindexIssueDependenciesJob < Repositories::RepositoryHydroMessageJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :hydro_reindex_issue_dependencies

  sig { void }
  def perform
    return if FeatureFlag.vexi.enabled?(:reindex_issue_dependencies_kill_switch, default: false)

    if topic.match(/github\.v1\.AccountRename$/)
      renamed_account_id = message.dig(:account, :id)

      # Get repo ids for all repos owned by the renamed account.
      renamed_account_repo_ids = Repository.where(owner_id: renamed_account_id).pluck(:id)

      # Re-index issue dependencies for each repo.
      # Ignore issues in a renamed account's repos, as they are re-indexed via update_repos_after_rename on rename! in the User model.
      renamed_account_repo_ids.each do |repo_id|
        BatchReindexIssueDependenciesJob.perform_later(
          repository_id: repo_id,
          repo_ids_to_ignore: renamed_account_repo_ids
        )
      end
    elsif topic.match(/github\.repositories\.v1\.(Renamed|Transferred)$/)
      return if repository.nil?
      return unless repository.has_issues?

      # Bulk re-index all issues in the given repo.
      Search.add_to_search_index("bulk_issues", repository.id, "purge" => true)

      # Re-index issue dependencies
      # Ignore issues in the transferred or renamed repo, as they were re-indexed prior to this step.
      BatchReindexIssueDependenciesJob.perform_later(
        repository_id: repository.id,
        repo_ids_to_ignore: [repository.id]
      )
    end
  end
end
