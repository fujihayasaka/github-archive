# typed: true
# frozen_string_literal: true
#
# When a user deletes a branch from either the API or the web UI,
# we enqueue a job to destroy any relevant BranchIssueReferences asynchronously.
#
# This is a different use case than the `destroy_dependents_in_background :linked_branches`
# declared in `Issue::BranchIssueReferenceDependency`
class DestroyBranchIssueReferencesJob < ApplicationJob
  queue_as :destroy_branch_issue_references

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, branch_name)
    repo = Repository.find_by(id: repository_id)

    # It's possible that the repository has been deleted since the job was enqueued.
    # This is highly unlikely, but if the repo doesn't exist we still want to delete
    # any branches that reference it.
    # If the repo and the branch both still exist, we don't want to delete references to to the branch
    return if repo && repo.heads.find(branch_name)

    issue_refs_to_remove = BranchIssueReference.by_branch_name(branch_name).by_repo(repository_id)

    with_write do
      issue_refs_to_remove.each do |ref|
        BranchIssueReference.throttle_with_retry { ref.destroy }
      end
    end
  end
end
