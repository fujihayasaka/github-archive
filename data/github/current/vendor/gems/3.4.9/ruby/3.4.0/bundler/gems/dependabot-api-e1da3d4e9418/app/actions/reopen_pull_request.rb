# frozen_string_literal: true

require "github_helpers"

class ReopenPullRequest
  attr_reader :pull_request

  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    Statesman::Machine.retry_conflicts do
      begin
        recreate_branch
        reopen_pull_request

        pull_request.transition_to!(:up_to_date) unless pull_request.in_state?(:up_to_date, :updating)
      rescue Octokit::UnprocessableEntity => e
        error_msg = e.message.downcase
        raise unless error_msg.include?("no history in common") ||
                     error_msg.include?("no new commits") ||
                     error_msg.include?("branch has been deleted") ||
                     error_msg.include?("branch was force-pushed")

        create_reopen_not_possible_comment(e)
      end

      pull_request
    end
  end

  private

  def recreate_branch
    return if branch_exists?

    installation_github_client.create_ref(
      pull_request.repo.github_id,
      "heads/#{github_details.head.ref}",
      github_details.head.sha,
    )
  rescue Octokit::UnprocessableEntity => e
    raise unless e.message.match?(/Reference already exists/i)
  end

  def reopen_pull_request
    installation_github_client.update_pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
      state: "open",
    )
  end

  def branch_exists?
    branch_ref = installation_github_client.ref(
      pull_request.repo.github_id,
      "heads/#{github_details.head.ref}",
    )
    if branch_ref.is_a?(Array)
      branch_ref.any? { |r| r.ref == "refs/heads/#{github_details.head.ref}" }
    else
      branch_ref.ref == "refs/heads/#{github_details.head.ref}"
    end
  rescue Octokit::NotFound
    false
  end

  def github_details
    @github_details ||= fetch_pull_request_from_github
  end

  def fetch_pull_request_from_github
    installation_github_client.pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  # rubocop:disable Metrics/MethodLength
  def create_reopen_not_possible_comment(error)
    error_msg = error.message.downcase
    msg =
      if error_msg.include?("no history in common")
        "Dependabot tried to reopen this PR, but was told that it no longer "\
        "has any history in common with the base branch (and therefore "\
        "couldn't be reopened)."
      elsif error_msg.include?("no new commits")
        "Dependabot tried to reopen this PR, but was told that it doesn't "\
        "include any commits that aren't already on the base branch (and "\
        "therefore couldn't be reopened)."
      elsif error_msg.include?("branch has been deleted")
        "Dependabot tried to reopen this PR, but was told that the target "\
        "branch has been deleted (and therefore that this PR couldn't be "\
        "reopened)."
      elsif error_msg.include?("branch was force-pushed")
        "Dependabot tried to reopen this PR, but was told that its branch "\
        "has been force pushed or recreated since it was closed (and "\
        "therefore can't be restored by GitHub)."
      else
        raise "Unexpected error: #{error.message}"
      end

    CreateComment.new(pull_request: pull_request, comment_body: msg).run
  end
  # rubocop:enable Metrics/MethodLength

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end
end
