# frozen_string_literal: true

module HandleWebhook
  class PullRequestReview
    attr_reader :webhook_body

    def initialize(webhook_body:, headers:)
      @webhook_body = webhook_body
      @headers = headers
    end

    def run
      return unless dependabot_pr

      if approval_that_should_trigger_a_merge?
        trigger_merge_request
        dependabot_pr.event_stream.record_event(Activity::PullRequestEvents::APPROVED,
                                                tags: { merge_requested: true })
      else
        dependabot_pr.event_stream.record_event(Activity::PullRequestEvents::APPROVED,
                                                tags: { merge_requested: false })
      end
      handle_body_as_issue_comment
    end

    private

    def approval_that_should_trigger_a_merge?
      return false unless dependabot_pr.account.merge_on_approval?
      return false if dependabot_pr.automerge_block_requested?
      return false unless approval?

      %w(submitted edited).include?(webhook_body.fetch(:action))
    end

    def trigger_merge_request
      HandlePullRequestCommentJob.perform_later(
        action: "HandleWebhook::IssueComment::HandleMergeRequest",
        requester_id: webhook_body.fetch(:review).fetch(:user).fetch(:id),
        keyword_args: {
          pull_request: dependabot_pr,
          requester: webhook_body.fetch(:review).fetch(:user).fetch(:login),
          comment_id: nil,
          comment_type: :review,
          triggered_by_review_approval: true,
        },
      )
    end

    def handle_body_as_issue_comment
      HandleWebhook::IssueComment.new(webhook_body: webhook_body, headers: @headers).run
    end

    def approval?
      webhook_body.fetch(:review).fetch(:state) == "approved"
    end

    def dependabot_pr
      return @dependabot_pr if defined? @dependabot_pr

      @dependabot_pr = ::PullRequest.joins(:repo).find_by(
        repos: { github_id: webhook_body[:repository][:id] },
        github_number: webhook_body.fetch(:pull_request).fetch(:number),
      )
    end
  end
end
