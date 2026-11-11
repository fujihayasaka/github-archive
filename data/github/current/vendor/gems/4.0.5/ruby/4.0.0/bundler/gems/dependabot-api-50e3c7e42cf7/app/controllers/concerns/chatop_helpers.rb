# frozen_string_literal: true

module ChatopHelpers
  extend ActiveSupport::Concern

  private

  # Parses a pull request reference and returns the associated UpdateJob.
  # Supports both URL format (https://github.com/owner/repo/pull/123)
  # and short format (owner/repo#123).
  #
  # @param pull_request_ref [String] The pull request reference
  # @return [UpdateJob, nil] The update job associated with the pull request, or nil if not found
  def find_update_job_from_pr(pull_request_ref)
    match = parse_pull_request_ref(pull_request_ref)
    return nil unless match

    account_login, repo_name, pr_number = match.captures
    pull_request = find_pull_request(account_login, repo_name, pr_number)
    pull_request&.update_job
  end

  def parse_pull_request_ref(pull_request_ref)
    # Try URL format first (e.g., https://github.com/owner/repo/pull/123)
    url_match = pull_request_ref.match(%r{github\.com/([^/]+)/([^/]+)/pull/(\d+)})
    # Fall back to short format (e.g., owner/repo#123)
    short_match = pull_request_ref.match(%r{\A([^/]+)/([^/]+)#(\d+)\z})
    url_match || short_match
  end

  def find_pull_request(account_login, repo_name, pr_number)
    account = Account.find_by(github_login: account_login)
    return nil unless account

    repo = Repo.find_by(account: account, name: repo_name)
    return nil unless repo

    repo.pull_requests.find_by(github_number: pr_number)
  end
end
