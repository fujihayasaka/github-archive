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

      dependabot_pr.event_stream.record_event(Activity::PullRequestEvents::APPROVED, tags: { merge_requested: false })
      handle_body_as_issue_comment
    end

    private

    def handle_body_as_issue_comment
      HandleWebhook::IssueComment.new(webhook_body: webhook_body, headers: @headers).run
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
