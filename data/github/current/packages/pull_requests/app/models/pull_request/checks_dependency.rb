# typed: true
# frozen_string_literal: true

module PullRequest::ChecksDependency
  extend T::Helpers

  requires_ancestor { PullRequest }
  # Internal: what are the matching CheckSuites for the given sha on this PR?
  #
  # sha  - The commit sha to filter CheckSuites by. Defaults to the last commit
  #        on this PR.
  #
  # Returns an ActiveRecord::Relation of CheckSuite objects.
  def matching_check_suites(head_sha: changed_commits.last&.oid)
    T.must(repository).check_suites.where(head_sha: head_sha, hidden: false)
  end

  # Internal: The matching Actions CheckSuites for the given sha on this PR with conclusion action_required
  #
  # sha  - The commit sha to filter CheckSuites by. Defaults to the last commit
  #        on this PR.
  #
  # Returns an Array of CheckSuite objects.
  def action_required_check_suites(head_sha: changed_commits.last&.oid)
    T.must(repository).check_suites.where(head_sha: head_sha, hidden: false, conclusion: :action_required).filter(&:actions_app?)
  end

  # The number of unique check runs for the matching check suites for this PR
  # Does not include statuses
  #
  # Returns an integer.
  def latest_check_runs_count
    return 0 unless changed_commits.last

    matching_check_suites.collect(&:latest_check_runs_count).sum
  end
end
