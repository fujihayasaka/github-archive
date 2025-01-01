# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Notifyd
  # Publish notifyd message
  #
  # Notifyd messages are expected to be published by calling Notifyd::NotifyPublisher
  # This job was created primarily to allow publishing a notifyd message asynchronously
  # and allow other processes to be run before publishing the message. E.g hamzo to check spaminess.
  class PublishNotifyMessageJob < ApplicationJob

    queue_as :notifyd_publish
    retry_on_dirty_exit
    retry_on_recoverable_exceptions wait: :polynomially_longer, attempts: 20
    retry_on ::Aqueduct::Client::ClientError, wait: :polynomially_longer, attempts: 20
    retry_on Notifyd::Aqueduct::UnavailableError, wait: :polynomially_longer, attempts: 20

    def perform(actor_id:, subject_id:, subject_klass:, triggered_at:, context: {})
      subject = subject_klass.constantize.find_by_id(subject_id)

      # Since the job runs asynchronously, we need to make sure the subject is still there
      if subject.blank?
        GitHub.dogstats.increment("notifyd.publish_notify_message_job.subject_missing")
        GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:skipped reason:subject_missing])
        return
      end

      adapter = Notifyd::SubjectAdapter.adapter_for_subject(subject, context)
      if !adapter.present?
        GitHub.dogstats.increment("notifyd.delivery", tags: %w[type:notify status:skipped reason:adapter_missing])
        return
      end

      args = {
        actor_id: actor_id,
        repository_id: adapter.repository_id,
        owner_id: adapter.owner_id,
        owner_type: adapter.owner_type,
        authzd_attributes: adapter.authzd_attributes,
        saml_enforcement: adapter.saml_enforcement,
        mobile_layout: adapter.mobile_layout,
        email_layout: adapter.email_layout,
        explicit_recipients: adapter.explicit_recipients,
        subject: subject,
        related_topics: adapter.related_topics,
        triggered_at: triggered_at,
        trigger: adapter.trigger,
        attributes: adapter.attributes,
        feature_switches: adapter.feature_switches,
        reason_groups: adapter.reason_groups,
        notification_id: adapter.notification_id,
      }

      Notifyd::NotifyPublisher.new.publish(**args)
    end

    def stats_tags
      super + ["subject:#{arguments.first[:subject_klass].underscore}"]
    end
  end
end
