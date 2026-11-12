# frozen_string_literal: true

module HandleWebhook
  class CheckSuite
    attr_reader :webhook_body

    def initialize(webhook_body:)
      @webhook_body = webhook_body
    end

    def run
      return unless dependabot_branch?

      update_pr_ci_statuses
      enqueue_pr_merges if success? && completed?
      enqueue_failure_comment if completed? && !success?
    end

    private

    def update_pr_ci_statuses
      affected_dependabot_prs.each do |pr|
        UpdatePullRequestCiStatusJob.perform_later(
          pull_request: pr,
          refs_to_check: [webhook_body[:check_suite][:head_sha]],
        )
      end
    end

    def enqueue_pr_merges
      pull_requests_awaiting_merge.each do |pr|
        MergePullRequestJob.
          set(wait_until: Time.now.utc + rand(0..60).seconds).
          perform_later(pull_request: pr)
      end
    end

    def enqueue_failure_comment
      pull_requests_awaiting_merge.each do |pr|
        CreateCheckOrStatusFailureCommentJob.perform_later(pull_request: pr)
      end
    end

    def success?
      %w(success neutral).include?(webhook_body[:check_suite][:conclusion])
    end

    def completed?
      webhook_body[:check_suite][:status] == GitHub::CheckRun::Status::COMPLETED
    end

    def dependabot_branch?
      webhook_body[:check_suite][:head_branch]&.include?("dependabot")
    end

    def affected_dependabot_prs
      [
        *pull_requests_with_matching_head_commit,
        *pull_requests_with_matching_base_commit,
        *pull_requests_with_matching_dependabot_commit,
      ].uniq
    end

    def pull_requests_for_repo
      ::PullRequest.exclude_pending.for_repo_github_id(webhook_body[:repository][:id])
    end

    def pull_requests_with_matching_dependabot_commit
      @pull_requests_with_matching_dependabot_commit ||=
        pull_requests_for_repo.where(
          dependabot_commit_sha: webhook_body[:check_suite][:head_sha],
        )
    end

    def pull_requests_with_matching_head_commit
      @pull_requests_with_matching_head_commit ||=
        pull_requests_for_repo.where(
          head_commit_sha: webhook_body[:check_suite][:head_sha],
        )
    end

    def pull_requests_with_matching_base_commit
      @pull_requests_with_matching_base_commit ||=
        pull_requests_for_repo.where(
          base_commit_sha: webhook_body[:check_suite][:head_sha],
        )
    end

    def pull_requests_awaiting_merge
      pull_requests_with_matching_head_commit.open.
        includes(:update_config, :updated_dependencies, :account).
        select(&:merge_requested?)
    end
  end
end
