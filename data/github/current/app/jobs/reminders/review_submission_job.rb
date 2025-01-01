# typed: false
# frozen_string_literal: true

module Reminders
  class ReviewSubmissionJob < RealTimeJob
    resolve_tenant_context do |kwargs|
      pull_request_review = PullRequestReview.find_by(id: kwargs[:pull_request_review_id])
      repository = pull_request_review&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(pull_request_review_id:, event_at:, transaction_id:)
      pull_request_review = PullRequestReview.find(pull_request_review_id)
      organization = pull_request_review.pull_request.repository.owner

      events = review_submission_events(pull_request_review, organization)
      events += review_comment_events(pull_request_review, organization)

      queue_reminder_events(events)
    end

    def review_submission_events(pull_request_review, organization)
      events = Reminders::ReviewSubmissionFinder.events(pull_request_review)

      if pull_request_review.commented?
        if single_comment_review?(pull_request_review)
          review_comment = pull_request_review.review_comments.first

          events += Reminders::CommentFinder.events(
            body: review_comment.body,
            pull_request: pull_request_review.pull_request,
            actor: review_comment.user,
            subject: review_comment,
            url: review_comment.permalink,
          )
        else
          events += Reminders::CommentFinder.events(
            body: pull_request_review.body,
            pull_request: pull_request_review.pull_request,
            actor: pull_request_review.user,
            subject: pull_request_review,
            url: pull_request_review.permalink,
          )
        end
      end

      events += Reminders::MentionFinder.events(
        body: pull_request_review.body,
        actor: pull_request_review.user,
        pull_request: pull_request_review.pull_request,
        subject: pull_request_review,
        url: pull_request_review.permalink,
      )

      events
    end

    def review_comment_events(pull_request_review, organization)
      events = []

      pull_request_review.review_comments.includes(:user).map do |review_comment|
        events += Reminders::MentionFinder.events(
          body: review_comment.body,
          actor: review_comment.user,
          pull_request: pull_request_review.pull_request,
          subject: review_comment,
          url: review_comment.permalink,
        )

        events += Reminders::CommentReplyFinder.events(review_comment)
      end

      events
    end

    private

    def single_comment_review?(pull_request_review)
      pull_request_review.body.blank? && pull_request_review.review_comments.count == 1
    end
  end
end
