# frozen_string_literal: true
# typed: false

require "github_helpers"

class CreateComment
  extend T::Sig

  CommentablePullRequest = T.type_alias { T.any(PullRequest, Stubs::PullRequest) }

  sig { params(comment_body: String, pull_request: CommentablePullRequest).void }
  def initialize(comment_body:, pull_request: nil)
    @pull_request = pull_request
    @comment_body = comment_body

    raise unless pull_request
  end

  sig { void }
  def run
    add_comment
  rescue *SynchronizeRepoState::HANDLED_ERRORS, Octokit::Unauthorized
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.create_comment",
    ).run
  rescue Octokit::Forbidden => e
    raise unless e.message.include?("Repository was archived")

    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.create_comment",
    ).run
  end

  private

  sig { returns(CommentablePullRequest) }
  attr_reader :pull_request

  sig { returns(String) }
  attr_reader :comment_body

  sig { void }
  def add_comment
    installation_github_client.add_comment(
      pull_request.repo.github_id,
      pull_request.github_number,
      comment_body,
    )
  rescue Octokit::Forbidden => e
    raise unless e.message.include?("issue is locked")
  end

  sig { returns(GitHubHelpers::ClientWithRetries) }
  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end
end
