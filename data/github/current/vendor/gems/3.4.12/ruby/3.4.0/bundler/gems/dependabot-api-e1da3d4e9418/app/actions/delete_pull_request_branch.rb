# frozen_string_literal: true

require "github_helpers"

class DeletePullRequestBranch
  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    return unless pull_request.repo.account.active?
    return unless github_pr_details.state == "closed"
    return if open_prs_using_this_branch?(github_pr_details.head.ref)

    installation_github_client.delete_branch(
      pull_request.repo.github_id,
      github_pr_details.head.ref,
    )
  rescue Octokit::UnprocessableEntity => e
    return if ignored_error?(e)

    raise
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.delete_pull_request_branch",
    ).run
  end

  private

  attr_reader :pull_request

  def ignored_error?(error)
    # Ignore races to delete the pull request's branch
    return true if error.message.include?("Reference does not exist")

    # Ignore archived repos
    return true if error.message.include?("Repository was archived")

    # Ignore attempts to delete protected branches
    if error.message.include?("protected branch") ||
       error.message.include?("You're not authorized to push to this branch") ||
       error.message.include?("Cannot delete this branch")
      return true
    end

    false
  end

  def github_pr_details
    @github_pr_details ||= fetch_pull_request_from_github
  end

  def open_prs_using_this_branch?(branch_name)
    installation_github_client.pull_requests(
      pull_request.repo.github_id,
      {
        head: "#{pull_request.account.github_login}:#{branch_name}",
        state: "open",
      }
    ).any?
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
