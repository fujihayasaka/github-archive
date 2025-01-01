# typed: true
# frozen_string_literal: true

module Reminders
  class PullRequestMergeConflictJob < RealTimeJob
    resolve_tenant_context do |kwargs|
      pull_request = PullRequest.find_by(id: kwargs[:pull_request_id])
      repository = pull_request&.repository
      if repository
        Business.find_by(id: repository.tenant_id)
      end
    end

    def perform(pull_request_id:, event_at:, transaction_id:)
      pull_request = PullRequest.find(pull_request_id)

      type = :merge_conflict
      reminder = PersonalReminder.for_remindable(pull_request.repository&.owner).
        for_event_type(type).
        find_by(user_id: pull_request.user_id)

      conflict = pull_request.conflict
      if conflict && reminder
        events = [
          Reminders::RealTimeEvent.new(
            # Because this job isn't run immediately after an action, there may
            # be many commits pushed by multiple people. In this case, there is
            # no single actor. Thankfully, the actor that created the conflicts
            # doesn't really matter. What matters is that the author's pull request
            # now has merge conflicts. For this reason, we always set the actor to
            # the pull request author.
            actor: pull_request.user,
            context: { conflicting_files: conflict.filenames },
            type: type,
            pull_request_ids: [pull_request.id],
            reminder: reminder,
            repository_id: pull_request.repository_id,
          ),
        ]

        queue_reminder_events(events)
      end
    end
  end
end
