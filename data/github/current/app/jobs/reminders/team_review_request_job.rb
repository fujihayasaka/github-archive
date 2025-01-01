# typed: true
# frozen_string_literal: true

module Reminders
  class TeamReviewRequestJob < RealTimeJob
    resolve_tenant_context do |kwargs|
      pull_request = PullRequest.find_by(id: kwargs[:pull_request_id])
      repository = pull_request&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(actor_id:, requested_team_id:, event_at:, pull_request_id:, transaction_id:)
      actor = User.find(actor_id)
      requested_team = Team.find(requested_team_id)
      pull_request = PullRequest.find(pull_request_id)

      events = team_review_request_events(pull_request, actor, requested_team)

      queue_reminder_events(events)
    end

    def team_review_request_events(pull_request, actor, requested_team)
      type = :team_review_request
      organization = pull_request&.repository&.organization
      member_ids = Team.member_ids_of(requested_team.id, immediate_only: false)

      reminders = PersonalReminder.for_remindable(organization).
        for_event_type(type).
        where(user_id: member_ids).
        where.not(user_id: actor.id)

      reminders.map do |reminder|
        Reminders::RealTimeEvent.new(
          actor: actor,
          context: { requested_team_id: requested_team.id },
          type: type,
          pull_request_ids: [pull_request.id],
          reminder: reminder,
          repository_id: pull_request.repository_id,
        )
      end
    end
  end
end
