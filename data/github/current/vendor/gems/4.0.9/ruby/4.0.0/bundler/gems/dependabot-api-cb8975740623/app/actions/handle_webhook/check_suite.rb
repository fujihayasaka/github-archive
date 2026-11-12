# frozen_string_literal: true

module HandleWebhook
  class CheckSuite
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      # If the event has not completed, it will be followed up by another
      # event later when the status changes to a terminal value.  Dependabot currently
      # only performs lookups and comparisons on PRs with terminal CI statuses,
      # so we can skip processing these events.
      return unless completed? && dependabot_branch?

      update_pr_ci_statuses
    end

    private

    def completed?
      webhook_body[:check_suite][:status] == "completed"
    end

    def update_pr_ci_statuses
      affected_dependabot_prs.each do |pr|
        UpdatePullRequestCiStatusJob.set(scheduling_properties).perform_later(
          pull_request: pr,
          refs_to_check: [webhook_body[:check_suite][:head_sha]],
        )
      end
    end

    def scheduling_properties
      {
        wait: UpdatePullRequestCiStatusJob::DEBOUNCE_PERIOD,
      }
    end

    def dependabot_branch?
      webhook_body[:check_suite][:head_branch]&.include?("dependabot")
    end

    def affected_dependabot_prs
      @affected_dependabot_prs ||= [
        *pull_requests_with_matching_head_commit,
        *pull_requests_with_matching_base_commit,
        *pull_requests_with_matching_dependabot_commit,
      ].uniq
    end

    def pull_requests_for_repo
      ::PullRequest.exclude_pending.for_repo_github_id(webhook_body[:repository][:id])
    end

    def pull_requests_with_matching_dependabot_commit
      pull_requests_for_repo.where(
        dependabot_commit_sha: webhook_body[:check_suite][:head_sha],
      )
    end

    def pull_requests_with_matching_head_commit
      pull_requests_for_repo.where(
        head_commit_sha: webhook_body[:check_suite][:head_sha],
      )
    end

    def pull_requests_with_matching_base_commit
      pull_requests_for_repo.where(
        base_commit_sha: webhook_body[:check_suite][:head_sha],
      )
    end
  end
end
