# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Reminders
  class PullRequestMergedJob < RealTimeJob
    MERGED_EVENT_TYPE = :pull_request_merged

    resolve_tenant_context do |kwargs|
      pull_request = PullRequest.find_by(id: kwargs[:pull_request_id])
      repository = pull_request&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(pull_request_id:, actor_id:, event_at:, transaction_id:)
      actor = User.find(actor_id)
      pull_request = PullRequest.find(pull_request_id)

      events = personal_reminder_events(pull_request, actor)

      queue_reminder_events(events)
    end

    def personal_reminder_events(pull_request, actor)
      return [] if actor.id == pull_request.user_id

      organization = pull_request&.repository&.organization
      reminder = PersonalReminder.for_remindable(organization).for_event_type(MERGED_EVENT_TYPE).find_by(user_id: pull_request.user_id)

      if reminder
        [
          Reminders::RealTimeEvent.new(
            actor: actor,
            context: {},
            type: MERGED_EVENT_TYPE,
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
