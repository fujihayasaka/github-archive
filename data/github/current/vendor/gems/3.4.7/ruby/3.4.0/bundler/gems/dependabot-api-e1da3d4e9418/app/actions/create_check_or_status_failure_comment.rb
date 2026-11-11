# frozen_string_literal: true

require "github_helpers"

class CreateCheckOrStatusFailureComment
  include GitHub::Twirp::DependabotPullRequests::Helpers

  attr_reader :pull_request

  def initialize(pull_request:)
    @pull_request = pull_request
  end

  def run
    return unless wants_merge?
    return unless ci_failure?
    return if check_or_status_failure_comment_left_previously?

    create_check_or_status_failure_comment
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.create_check_or_status_failure_comment",
    ).run
  end

  private

  def wants_merge?
    pull_request.merge_requested?
  end

  def ci_failure?
    ci_status == resolve_ci_status_symbol(CiStatus::CI_STATUS_FAILURE)
  end

  def check_or_status_failure_comment_left_previously?
    dependabot_comments.any? { |c| c.body.include?("Dependabot won't merge") }
  end

  def create_check_or_status_failure_comment
    CreateComment.new(
      pull_request: pull_request,
      comment_body: comment_text,
    ).run
  end

  def comment_text
    "One of your CI runs failed on this pull request, so Dependabot won't "\
    "merge it.\n\n"\
    "Dependabot will still automatically merge this pull request if you amend "\
    "it and your tests pass."
  end

  def dependabot_comments
    all_pr_comments.select { |c| c.user.login == "dependabot[bot]" }
  end

  def all_pr_comments
    installation_github_client.issue_comments(
      pull_request.repo.github_id,
      pull_request.github_number,
      per_page: 100,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.
      new(account: pull_request.repo.account)
  end

  def ci_status
    @ci_status ||= pull_requests_client.
                   get_ci_status(repo: pull_request.repo, shas: [pull_request.head_commit_sha]).
                   fetch(pull_request.head_commit_sha, nil)
  end

  def pull_requests_client
    @pull_requests_client ||=
      GitHub::Twirp::DependabotPullRequests.new(
        client: Dependabot::Application.github_twirp_client,
        tenant: pull_request.repo.account.tenant
      )
  end
end
