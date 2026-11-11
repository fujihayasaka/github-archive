# typed: true
# frozen_string_literal: true

class SendCodeScanningAlertAssignmentNotificationJob < HydroMessageJob
  retry_on_dirty_exit
  queue_as :hydro_send_code_scanning_alert_assignment_notification

  sig { void }
  def perform
    new_assignees_ids = message[:current_assigned_user_ids] - message[:previous_assigned_user_ids]
    return if new_assignees_ids.empty?

    repository = Repository.find_by(id: message[:repository_id])
    return unless repository.present?
    return unless FeatureFlag.vexi.enabled?(:code_scanning_alert_event_notifications, repository, repository.owner, default: false)

    assignees = User.where(type: "User", id: new_assignees_ids)
    return unless assignees.any?

    actor = User.find_by(id: message[:actor_id])
    return unless actor.present?

    subject = CodeScanning::AlertEventNotification.new(
      alert_number: message[:alert_number],
      repository:,
    )

    # Notify new assignee
    assignees.each do |assignee|
      context = {
        operation: Notifyd::Operations::CodeScanningAlertOperation::Assigned,
        actor:,
        assignee:,
      }
      adapter = Notifyd::SubjectAdapter.adapter_for_subject(subject, context)
      args = {
        actor_id: message[:actor_id],
        repository_id: repository.id,
        owner_id: adapter.owner_id,
        owner_type: adapter.owner_type,
        authzd_attributes: adapter.authzd_attributes,
        saml_enforcement: adapter.saml_enforcement,
        mobile_layout: adapter.mobile_layout,
        email_layout: adapter.email_layout,
        explicit_recipients: adapter.explicit_recipients,
        subject:,
        related_topics: adapter.related_topics,
        triggered_at: Time.now,
        trigger: adapter.trigger,
        attributes: adapter.attributes,
        feature_switches: adapter.feature_switches,
        reason_groups: adapter.reason_groups,
        notification_id: adapter.notification_id,
      }
      Notifyd::NotifyPublisher.new.publish(**args)
    end
  end
end
