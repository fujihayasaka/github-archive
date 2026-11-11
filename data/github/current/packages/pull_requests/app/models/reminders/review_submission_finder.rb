# typed: true
# frozen_string_literal: true

module Reminders
  class ReviewSubmissionFinder
    def self.events(pull_request_review)
      new(pull_request_review).events
    end

    attr_reader :actor, :context, :organization, :pull_request, :pull_request_review, :subject, :type
    def initialize(pull_request_review)
      @pull_request_review = pull_request_review

      @actor = pull_request_review.user
      @pull_request = pull_request_review.pull_request
      @subject = pull_request_review

      @organization = pull_request.repository.organization
      @type = :review_submission
      @context = {
        comment_body: pull_request_review.body,
        review_state: PullRequestReview.state_name(pull_request_review.state),
      }
    end

    def events
      return [] unless valid?

      reminders.map do |reminder|
        Reminders::RealTimeEvent.new(
          actor: actor,
          context: context,
          type: type,
          reminder: reminder,
          pull_request_ids: [pull_request.id],
          repository_id: pull_request.repository_id,
          subject: pull_request_review,
        )
      end
    end

    def reminders
      @reminders ||= PersonalReminder.
        for_remindable(organization).
        for_event_type(type).
        where(user_id: pull_request.user_id)
    end

    def relevant_state?
      pull_request_review.approved? || pull_request_review.changes_requested?
    end

    def valid?
      pull_request_review && organization && relevant_state?
    end
  end
end
