# typed: true
# frozen_string_literal: true

module Reminders
  class UserReviewRequestJob < RealTimeJob
    resolve_tenant_context do |kwargs|
      pull_request = PullRequest.find_by(id: kwargs[:pull_request_id])
      repository = pull_request&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(actor_id:, requested_reviewer_id:, event_at:, pull_request_id:, transaction_id:)
      actor = User.find(actor_id)
      requested_reviewer = User.find(requested_reviewer_id)
      pull_request = PullRequest.find(pull_request_id)

      events = user_review_request_events(pull_request, actor, requested_reviewer)

      queue_reminder_events(events)
    end

    def user_review_request_events(pull_request, actor, requested_reviewer)
      return [] if actor == requested_reviewer

      type = :review_request
      organization = pull_request&.repository&.organization
      reminder = PersonalReminder.for_remindable(organization).
        for_event_type(type).
        find_by(user_id: requested_reviewer.id)

      if reminder
        [
          Reminders::RealTimeEvent.new(
            reminder: reminder,
            actor: actor,
            type: type,
            context: { requested_id: requested_reviewer.id },
            pull_request_ids: [pull_request.id],
            repository_id: pull_request.repository_id,
          ),
        ]
      else
        []
      end
    end
  end
end
