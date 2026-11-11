# typed: strict
# frozen_string_literal: true

module CodeScanning
  class SendAlertsDismissalNotificationJob < ApplicationJob
    queue_as :code_scanning

    retry_on_dirty_exit

    sig { params(actor_id: Integer, repository_id: Integer, alert_numbers: T::Array[Integer]).void }
    def perform(actor_id:, repository_id:, alert_numbers:)
      repository = Repository.find_by(id: repository_id)
      return unless repository.present?
      return unless FeatureFlag.vexi.enabled?(:code_scanning_alert_event_notifications, repository, repository.owner, default: false)

      repo_numbers = alert_numbers.map do |alert_number|
        Turboscan::Proto::RepoNumber.new(
          repository_id:,
          number: alert_number,
        )
      end
      alerts_response = GitHub::Turboscan.alerts_by_repo(
        repository_ids: [repository_id],
        repo_numbers:,
        owner_ids: [repository.owner_id],
        limit: 25, # We should not have more than 25 alerts dismissed at once.
      )

      raise StandardError.new(alerts_response&.error&.msg || "No response when fetching alerts") if alerts_response.nil? || alerts_response.error.present?

      assigned_user_ids = alerts_response.data.results.flat_map do |repo_result|
        alert = repo_result.result
        next [] unless alert.present?
        alert.assigned_user_ids
      end

      assignees = User.where(type: "User", id: assigned_user_ids.uniq).index_by(&:id)
      return unless assignees.any?

      actor = User.find_by(id: actor_id)
      return unless actor.present?

      alerts = alerts_response.data.results.each do |repo_result|
        alert = repo_result.result
        next unless alert.present?

        alert_assignees = alert.assigned_user_ids.map { |user_id| assignees[user_id] }.compact
        next if alert_assignees.empty?

        subject = CodeScanning::AlertEventNotification.new(
          alert_number: alert.number,
          repository:,
        )
        context = {
          operation: Notifyd::Operations::CodeScanningAlertOperation::Dismissed,
          actor:,
          assignees: alert_assignees,
        }

        adapter = Notifyd::SubjectAdapter.adapter_for_subject(subject, context)
        args = {
          actor_id:,
          repository_id:,
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
end
