# typed: true
# frozen_string_literal: true

module Reminders
  class PullRequestAssignedJob < RealTimeJob
    resolve_tenant_context do |kwargs|
      pull_request = PullRequest.find_by(id: kwargs[:pull_request_id])
      repository = pull_request&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(actor_id:, assignee_id:, pull_request_id:, event_at:, transaction_id:)
      actor = User.find(actor_id)
      assignee = User.find(assignee_id)
      pull_request = PullRequest.find(pull_request_id)

      events = pull_request_assigned_events(pull_request, actor, assignee)

      queue_reminder_events(events)
    end

    def pull_request_assigned_events(pull_request, actor, assignee)
      return [] if actor == assignee

      type = :assignment
      organization = pull_request&.repository&.organization
      reminder = PersonalReminder.for_remindable(organization).for_event_type(type).find_by(user_id: assignee.id)

      if reminder
        [
          Reminders::RealTimeEvent.new(
            actor: actor,
            context: { assignee_id: assignee.id },
            type: type,
            pull_request_ids: [pull_request.id],
            reminder: reminder,
            repository_id: pull_request.repository_id,
          ),
        ]
      else
        []
      end
    end
  end
end
