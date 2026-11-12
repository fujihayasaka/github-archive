# frozen_string_literal: true

require "github_helpers"

class UpdatePullRequestBaseBranch
  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    return if github_details.state == "closed"
    return if new_target_branch == github_details.base.ref

    # If the current base branch doesn't match the one we're targeting then we
    # need to update this PR. The update strategy depends on whether the old
    # base branch is behind the new one or ahead (or diverged) of it.
    new_branch_status = branch_status(new_target_branch)

    if %w(ahead identical).include?(new_branch_status)
      update_pr_base_branch_via_api
    else
      rebase_pr_to_trigger_branch_update
    end
  end

  private

  attr_reader :pull_request

  def update_pr_base_branch_via_api
    installation_github_client.update_pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
      base: new_target_branch,
    )
  rescue Octokit::UnprocessableEntity => e
    msg = e.message
    # If an update config is changed twice in quick succession then this action
    # will run twice, and (since it is called from an async job) may race to
    # change the base branch to the same ref twice, yielding this error.
    return if msg.include?("pull request already exists")

    # If the new branch already includes the commits from this PR we trigger
    # a rebase, which will close the PR.
    return rebase_pr_to_trigger_branch_update if msg.include?("no new commits")

    # Otherwise, this error is a surprise - re-raise it.
    raise
  end

  def rebase_pr_to_trigger_branch_update
    return unless pull_request.update_config.automatically_rebase_prs?

    RebasePullRequestIfNewCommitsJob.perform_later(pull_request: pull_request)
  end

  def new_target_branch
    @new_target_branch ||=
      pull_request.update_config.target_branch ||
      github_details.base.repo.default_branch
  end

  def branch_status(branch)
    installation_github_client.compare(
      pull_request.repo.github_id,
      github_details.base.ref,
      branch,
    ).status
  rescue Octokit::NotFound
    "deleted'"
  end

  def github_details
    @github_details ||=
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
