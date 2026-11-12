# frozen_string_literal: true

require "github_helpers"

class CreateComment
  def initialize(comment_body:, pull_request: nil)
    @pull_request = pull_request
    @comment_body = comment_body

    raise unless pull_request
  end

  def run
    add_comment
  rescue *SynchronizeRepoState::HANDLED_ERRORS, Octokit::Unauthorized
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.create_comment",
    ).run
  end

  private

  attr_reader :pull_request, :comment_body

  def add_comment
    installation_github_client.add_comment(
      pull_request.repo.github_id,
      pull_request.github_number,
      comment_body,
    )
  rescue Octokit::Forbidden => e
    raise unless e.message.include?("issue is locked")
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end
end
