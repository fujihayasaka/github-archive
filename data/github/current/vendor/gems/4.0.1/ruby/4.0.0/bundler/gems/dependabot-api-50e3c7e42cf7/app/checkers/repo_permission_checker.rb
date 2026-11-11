# frozen_string_literal: true

require "github_helpers"

class RepoPermissionChecker
  class InaccessibleRepo < StandardError
    attr_reader :repo

    def initialize(repo)
      @repo = repo
      super("Could not access gh.repo.id: #{repo.github_id}")
    end
  end

  def initialize(repo:, user_github_login:)
    @repo = repo
    @user_github_login = user_github_login
  end

  def permission_level
    raise InaccessibleRepo, repo unless repo.account.active?

    @user_permission ||=
      GitHubHelpers::ClientWithRetries.new(
        account: repo.account,
        etag_caching: true,
      ).permission_level(
        repo.github_id,
        user_github_login
      ).permission
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: repo,
      event_source: "action.repo_permission_checker",
    ).run

    raise InaccessibleRepo, repo
  end

  private

  attr_reader :repo, :user_github_login
end
