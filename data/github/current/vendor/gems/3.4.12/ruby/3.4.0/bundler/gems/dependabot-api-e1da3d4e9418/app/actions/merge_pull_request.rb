# frozen_string_literal: true

require "github_helpers"

# Merges a Dependabot pull request. Doesn't do any checking of CI status,
# whether it's edited, etc. - that's the responsibility of the calling class.
class MergePullRequest
  class MergeNotPossible < StandardError; end

  def initialize(pull_request:, require_up_to_date: false)
    @pull_request = pull_request
    @require_up_to_date = require_up_to_date
  end

  def run
    return false if github_details.mergeable == false

    # The state "behind" is only used when a branch cannot be merged because
    # it is behind. We should automatically rebase in these cases.
    return false if github_details.mergeable_state == "behind"

    merge_on_github
  end

  private

  attr_reader :pull_request

  def require_up_to_date?
    @require_up_to_date
  end

  def merge_on_github
    # Dependabot may be rebasing the PR
    return false if require_up_to_date? && pull_request.in_state?(:updating)
    return false unless merge_pull_request

    branch_name = github_details.head.ref
    delete_branch(branch_name) unless open_prs_using_this_branch?(branch_name)

    true
  end

  def merge_pull_request
    perform_merge(pull_request: pull_request)
    true
  rescue Octokit::MethodNotAllowed => e
    if no_merge_allowed?(e)
      # Merge commits are disabled on the repo. Don't try to create them anymore
      pull_request.account.update!(create_merge_commits: false)
      retry
    end

    if e.message.include?("Squash merge") && !pull_request.squash_requested?
      # Squash merges *and* rebase merges are disabled on the repo. Use merge
      # commits
      pull_request.account.update!(create_merge_commits: true)
      retry
    end

    # Return false for errors that are transient (i.e., PR is closed or behind)
    return false if routine_error?(e)

    raise_merge_error(e)
  rescue Octokit::Forbidden
    raise if pull_request_files.none? { |f| f.start_with?(".github/") }

    raise_forbidden_files_error
  end

  def no_merge_allowed?(error)
    error.message.include?("Merge commits") ||
      error.message.include?("branch must not contain merge commits")
  end

  def raise_merge_error(error)
    if error.message.include?("Squash merges") && pull_request.squash_requested?
      raise MergeNotPossible, JSON.parse(error.response_body).fetch("message")
    end

    # Raise original error for unexpected errors
    raise unless user_action_required_error?(error)

    # Raise MergeNotPossible for permission-related errors
    raise MergeNotPossible, JSON.parse(error.response_body).fetch("message")
  end

  def raise_forbidden_files_error
    forbidden_files = pull_request_files.
                      select { |f| f.start_with?(".github/") }
    msg = "This pull request includes edits which prevent it being merged by "\
          "an app. The forbidden files are #{forbidden_files.join(', ')}."

    raise MergeNotPossible, msg
  end

  def routine_error?(error)
    return true if error.message.include?("Pull Request is not mergeable")
    return true if error.message.include?("Base branch was modified")
    return true if error.message.include?("Required status check")
    return true if error.message.include?("required status check")
    return true if error.message.include?("can't be rebased")
    return true if error.message.include?("requesting changes")
    return true if error.message.include?("Pull Request is in the merge queue")

    error.message.include?("Merge already in progress")
  end

  def user_action_required_error?(error)
    return true if error.message.include?("approving review")
    return true if error.message.include?("not authorized")
    return true if error.message.include?("Waiting on code owner review")
    return true if error.message.include?("Commits must have valid signatures.")
    return true if error.message.include?("Repository rule violations found")
    return true if error.message.include?("Changes must be made through the merge queue")

    false
  end

  def perform_merge(pull_request:)
    merge_method = "squash" if pull_request.squash_requested?
    merge_method ||=
      pull_request.account.create_merge_commits ? "merge" : "rebase"

    installation_github_client.merge_pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
      "",
      merge_method: merge_method,
    )
  rescue Octokit::MethodNotAllowed => e
    raise unless e.message.include?("Rebase merges")

    # We default to using rebase merges if a user doesn't want merge commits,
    # but if that fails try a squash merge
    merge_method = "squash"
    retry
  end

  def delete_branch(branch_name)
    installation_github_client.delete_branch(
      pull_request.repo.github_id,
      branch_name,
    )
  rescue Octokit::UnprocessableEntity => e
    # Ignore attempts to delete protected branches
    if e.message.include?("protected branch") ||
       e.message.include?("You're not authorized to push to this branch")
      return
    end

    # Ignore races to delete the pull request's branch
    return if e.message.include?("Reference does not exist")

    raise
  end

  def open_prs_using_this_branch?(branch_name)
    installation_github_client.pull_requests(
      pull_request.repo.github_id,
      {
        head: "#{pull_request.account.github_login}:#{branch_name}",
        state: "open",
      }
    ).reject { |pr| pr.number == pull_request.github_number }.any?
  end

  def github_details
    @github_details ||= fetch_pull_request_from_github
  end

  def pull_request_files
    @pull_request_files ||=
      installation_github_client.pull_request_files(
        pull_request.repo.github_id,
        pull_request.github_number,
      ).map(&:filename)
  end

  def fetch_pull_request_from_github
    installation_github_client.pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end
end
