# typed: true
# frozen_string_literal: true
#
class UpdateCloseIssueReferencesJob < ApplicationJob
  use_primaries ApplicationRecord::Collab, ApplicationRecord::IssuesPullRequests

  CONCURRENT_JOBS = 1
  LOCK_TTL = 10.minutes

  queue_as :update_close_issue_references

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock, wait: 10.minutes, attempts: 5

  resolve_tenant_context do |issue_id|
    issue = Issue.find_by(id: issue_id)
    repository = issue&.repository
    if repository
      Business.find_by(id: repository.tenant_id)
    end
  end

  def perform(issue_id)
    # a restraint lock allows sequential execution, with no discarding of
    # jobs even if the lock is taken. Consequently - no data should be missed.
    restraint = GitHub::Restraint.new
    restraint.lock!(restraint_lock_key(issue_id), CONCURRENT_JOBS, LOCK_TTL) do
      perform_in_lock(issue_id)
    end
  end

  private

  def restraint_lock_key(issue_id)
    "update_close_issue_references_job_restraint_#{issue_id}"
  end

  def perform_in_lock(issue_id)
    return unless pull_issue = Issue.find_by(id: issue_id)
    return unless pull = pull_issue.pull_request
    return unless pull.close_issues_on_merge_permitted?

    BranchIssueReference.link_pull_request(pull)

    author_close_issues = pull.calculate_close_issues(user: pull.user)

    editor = pull_issue.editor
    modifying_user_close_issues = if editor
      pull.calculate_close_issues(user: editor)
    else
      author_close_issues.dup
    end

    # Keep any refs that were previously created by the author or modifying user
    issue_ids_to_keep = (author_close_issues + modifying_user_close_issues).map(&:id).uniq
    refs_to_keep = pull.close_issue_references.includes(:issue).xref.where(issue_id: issue_ids_to_keep)
    refs_to_remove = pull.close_issue_references.xref - refs_to_keep

    refs_to_remove.each do |ref|
      CloseIssueReference.throttle_writes_with_retry { ref.destroy }
    end

    return if pull.spammy?

    # remove any pull_request issues before attempting to save reference, as
    # a pull request cannot close another pull request
    # only create new xrefs that the modifying user has permission to create
    issues_to_add = (modifying_user_close_issues - refs_to_keep.map(&:issue)).reject(&:pull_request?)

    issues_to_add.each do |issue|
      CloseIssueReference.throttle_writes_with_retry do
        pull.close_issue_references.create(issue: issue, actor_id: GitHub.context[:actor_id])
      end
    end
  end
end
