# typed: true
# frozen_string_literal: true

# Sends email notifications to users when they are assigned to a Dependabot alert.
# The caller is responsible for computing the delta (new assignees only) before
# calling this job to avoid re-notifying users who were already assigned.
class SendDependabotAlertAssignmentNotificationJob < ApplicationJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  queue_as :dependabot_alert_assignment_notifications

  sig do
    params(
      alert_id: Integer,
      new_assignee_ids: T::Array[Integer],
      assignor_id: T.nilable(Integer),
    ).void
  end
  def perform(alert_id:, new_assignee_ids:, assignor_id:)
    return if new_assignee_ids.empty?

    alert = RepositoryVulnerabilityAlert.find_by(id: alert_id)
    return unless alert.present?

    repository = alert.repository
    return unless repository.present?

    new_assignees = User.where(type: "User", id: new_assignee_ids)
    return unless new_assignees.any?

    assignor = assignor_id.present? ? User.find_by(id: assignor_id) : nil
    return unless assignor.present?

    # Send email notification to each new assignee
    new_assignees.each do |assignee|
      VulnerabilityMailer.user_assigned_to_alert(
        assignee: assignee,
        repository: repository,
        alert: alert,
        assignor: assignor,
      ).deliver_later
    end
  end
end
