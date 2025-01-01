# typed: true
# frozen_string_literal: true

module User::AssignmentDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  # Public: Can the user be assigned to an issue?
  #
  # Returns a Boolean.
  def assignable_to_issues?
    !spammy? && !suspended?
  end

  # Public: Unassign the user from all issues they were assigned to. If there's
  # an ActiveRecord error during this process, it'll be reported to Failbot
  # and execution will continue.
  #
  # scope - Optional scope restricting which issues the user should be
  #         unassigned from.
  #
  # Returns nothing.
  def clear_issue_assignments(scope: Issue)
    return unless user?

    scope.assigned_to(self).includes(:assignments).each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue.remove_assignees(self)

      if self.being_destroyed?
        construct_future_event do
          Hook::Event::IssuesEvent.new(
            action: :unassigned,
            issue_id: issue.id,
            actor_id: actor.try(:id),
            assignee_id: self.id,
            triggered_at: Time.now,
          )
        end
      end

      begin
        issue.save!
      rescue ActiveRecord::RecordInvalid => error
        log_issue_event_details(issue)
        Failbot.report(error)
      rescue ActiveRecord::ActiveRecordError => error
        Failbot.report(error)
      end
    end
  end

  # Internal: a temporary addition to log more info when saving a user's issue
  # fails. Ref https://github.com/github/github/issues/128215
  private def log_issue_event_details(issue)
    issue.events.reject(&:valid?).each do |event|
      GitHub.logger.info(
        "clear_issue_assignments.issue.save.fail",
        {
          "gh.issue.id": issue.id,
          "gh.actor.id": event.actor_id,
          "gh.issue.event.name": event.event,
          "gh.repo.id": event.repository_id
        }
      )
    end
  end
end
