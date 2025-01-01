# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Reminders
  class IssueCommentJob < RealTimeJob
    retry_on_dirty_exit

    resolve_tenant_context do |kwargs|
      issue_comment = ::IssueComment.find_by(id: kwargs[:issue_comment_id])
      repository = issue_comment&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    # Retry when expected records not found because replica may be behind.
    # If retries are exhausted, then log so we don't raise a non-actionable ActiveRecord::NotFound
    retry_on ActiveRecord::RecordNotFound, wait: 3.seconds, attempts: MAX_RETRY_ATTEMPTS do |_job, error|
      GitHub.logger.error("Stopped retrying IssueCommentJob after exhausting retry attempts", {
        "exception.type" => error.class.name,
        "exception.message" => error.message
      })
    end

    def perform(issue_comment_id:, event_at:, transaction_id:)
      issue_comment = ::IssueComment.find(issue_comment_id)
      actor = issue_comment.user
      return unless pull_request = issue_comment.issue&.pull_request

      events = Reminders::MentionFinder.events(
        body: issue_comment.body,
        actor: actor,
        pull_request: pull_request,
        subject: issue_comment,
        url: issue_comment.permalink
      )

      events += Reminders::CommentFinder.events(
        body: issue_comment.body,
        pull_request: pull_request,
        actor: actor,
        subject: issue_comment,
        url: issue_comment.permalink,
      )

      queue_reminder_events(events)
    end
  end
end
