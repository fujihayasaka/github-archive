# frozen_string_literal: true

require "github_helpers"

class ClosePullRequest
  class GitHubCloseBug < StandardError; end

  attr_reader :pull_request

  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    Statesman::Machine.retry_conflicts(3) do
      remove_pr_message_addendum if pull_request.in_state?(:updating)

      begin
        pr_details = close_pull_request
        branch_name = pr_details.head.ref
        delete_branch(branch_name) unless open_prs_using_this_branch?(branch_name)

        pull_request.transition_to(:closed) unless pull_request.in_state?(:merged)
      rescue Octokit::Forbidden => e
        raise unless e.message.include?("Repository was archived")
      rescue Octokit::NotFound
        raise unless pull_request_merged? || repo_deleted?
      end

      pull_request
    end
  end

  private

  def close_pull_request
    installation_github_client.close_pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  rescue Octokit::UnprocessableEntity => e
    raise GitHubCloseBug, e.message
  end

  def delete_branch(branch_name)
    installation_github_client.delete_branch(
      pull_request.repo.github_id,
      branch_name,
    )
  rescue Octokit::UnprocessableEntity, Octokit::Forbidden => e
    # Ignore races to delete the pull request's branch
    return if e.message.include?("Reference does not exist")

    # Ignore archived repos
    return if e.message.include?("Repository was archived")

    # Ignore attempts to delete protected branches
    if e.message.include?("protected branch") ||
       e.message.include?("You're not authorized to push to this branch") ||
       e.message.include?("Cannot delete this branch")
      return true
    end

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

  def remove_pr_message_addendum
    # Remove the "GitHub is rebasing this PR" comment, if present.
    regex = %r{\[//\]: # \(dependabot-start\).*\[//\]: # \(dependabot-end\)}m
    updated_body = github_details.body.to_s.gsub(regex, "").strip

    UpdatePullRequestBody.new(
      pull_request: pull_request,
      updated_body: updated_body,
    ).run
  end

  def github_details
    @github_details ||= fetch_pull_request_from_github
  end

  def pull_request_merged?
    return true if pull_request.in_state?(:merged)
    return false unless github_details.merged

    pull_request.transition_to!(:merged)
    true
  rescue Octokit::NotFound
    false
  end

  def repo_deleted?
    installation_github_client.repo(pull_request.repo.github_id)
    false
  rescue Octokit::NotFound
    true
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
