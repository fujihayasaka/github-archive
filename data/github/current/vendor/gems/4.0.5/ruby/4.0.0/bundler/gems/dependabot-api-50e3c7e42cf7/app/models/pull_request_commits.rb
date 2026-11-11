# frozen_string_literal: true

class PullRequestCommits
  def initialize(pull_request:)
    @pull_request = pull_request
  end
  # Commits tagged with [dependabot-skip] are filtered out, so that people
  # can set up automations to push to dependabot branches that we can ignore
  # and discard when rebasing/recreating.
  SKIP_REGEX = /\[dependabot[\s\-_]skip\]|\[skip[\s\-_]dependabot\]/i

  # Checks if the commits for a given pull request have been edited since
  # Dependabot opened it.
  #
  # @param head_sha [String] the latest known sha, typically the initial commit.
  # @param exclude_skip_commits [Bool] if we should exclude dependabot-skip
  # commits in the comparison.
  #
  # @return [Bool] wether or not the PR has been edited.
  def pr_has_been_edited?(head_sha:, exclude_skip_commits: true)
    return false if pull_request.dependabot_commit_sha == head_sha

    last_commit = relevant_commit_details(exclude_skip_commits).last&.commit
    return true unless last_commit
    return true unless created_by_dependabot?(last_commit.author.name)

    !created_by_dependabot?(last_commit.committer.name)
  end

  private

  attr_reader :pull_request

  def relevant_commit_details(exclude_skip_commits)
    if exclude_skip_commits
      unskipped_commit_details
    else
      commit_details
    end
  end

  def unskipped_commit_details
    commit_details.reject do |details|
      details.commit.message =~ SKIP_REGEX
    end
  end

  def dependabot_login
    "#{integration_name}[bot]"
  end

  def integration_name
    Prius.get(:github_integration_name)
  end

  def github_login
    "GitHub"
  end

  def commit_details
    @commit_details ||=
      installation_github_client.pull_request_commits(
        pull_request.repo.github_id,
        pull_request.github_number,
      )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: pull_request.repo.account
      )
  end

  def created_by_dependabot?(author)
    [dependabot_login, github_login].include?(author)
  end
end
