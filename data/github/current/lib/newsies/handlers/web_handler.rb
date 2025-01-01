# typed: true
# frozen_string_literal: true

module Newsies
  class WebHandler

    include GitHub::Tracing
    trace_method :deliver
    trace_method :force_deliver

    def handler_key
      :web
    end

    # Public: Handles the delivery for the User.
    #
    # delivery   - A Newsies::Delivery.
    # settings   - A Newsies::Settings object of the user receiving this
    #              notification.
    # event_time - Time of the notification generating event
    # reason     - (Optional) Symbol subscription reason for the user.
    # root_job_enqueued_at - Time the parent job was enqueued.
    #
    # Returns Newsies::Responses::Boolean instance.
    def deliver(delivery, settings, event_time:, reason: nil, root_job_enqueued_at: nil, priority: :high, extra_tags: [], inspector: nil, is_update: false, author: nil)
      return false unless deliver?(delivery.comment, settings)

      force_deliver(delivery, settings, event_time:, reason:, root_job_enqueued_at:, priority:, extra_tags:, inspector:, is_update:, author:)
    end

    # Internal: Delivers a web notification without checking if the delivery should actually be delivered.
    # This check is caller's responsibility.
    # This is only publicly available for internal use during notifications migration to notifyd,
    # it shouldn't be directly used otherwise.
    #
    # delivery   - A Newsies::Delivery.
    # settings   - A Newsies::Settings object of the user receiving this
    #              notification.
    # event_time - Time of the notification generating event
    # reason     - (Optional) Symbol subscription reason for the user.
    # root_job_enqueued_at - Time the parent job was enqueued.
    #
    # Returns Newsies::Responses::Boolean instance.
    def force_deliver(delivery, settings, event_time:, reason: nil, root_job_enqueued_at: nil, priority: :high, extra_tags: [], inspector: nil, is_update: false, author: nil)
      Newsies::NotificationEntry.insert(
        settings.id,
        delivery.summary,
        reason: reason,
        event_time: event_time,
      )

      settings.user&.notify_web_notifications_changed_socket_subscribers(Newsies::NotificationEntry.default_live_updates_wait)

      GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:success", "handler:#{handler_key}"])

      DeliveryLogger.log_to_splunk_and_hydro(
        delivery,
        user: settings.user,
        reason: reason,
        handler_key: handler_key,
        event_time: event_time,
        root_job_enqueued_at: root_job_enqueued_at,
        delivered: true,
      )

      DeliveryLogger.log_to_datadog(
        handler_key: handler_key,
        event_time: event_time,
        extra_tags: extra_tags,
      )

      true
    end

    private

    # Internal: Should this be delivered?
    #
    # comment  - A comment to be delivered
    # settings - A Newsies::Settings object of the user receiving this
    #            notification
    #
    # Returns Boolean
    def deliver?(comment, settings)
      if vulnerability_alert_notification?(comment)
        deliver_vulnerability_web = settings.vulnerability_web?
        unless deliver_vulnerability_web
          GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:filter", "filter:vulnerability_web", "handler:#{handler_key}"])
        end
        return deliver_vulnerability_web
      end

      return true if actions_notification?(comment) && settings.continuous_integration_web? && comment.deliver?(settings)
      return true unless comment.notifications_author

      is_author = comment.notifications_author.id == settings.id
      if is_author
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:filter", "filter:is_author", "handler:#{handler_key}"])
      end
      !is_author
    end

    def actions_notification?(comment)
      comment.is_a?(CheckSuiteEventNotification) ||
        comment.is_a?(WorkflowRunApprovalNotification)
    end

    def vulnerability_alert_notification?(comment)
      comment.is_a?(RepositoryVulnerabilityAlert::WebNotification) ||
        comment.is_a?(VulnerabilityAlertingEvent::SecurityAdvisoryNotification) ||
          comment.is_a?(VulnerabilityAlertingEvent::VulnerableRepositoryNotification)
    end
  end
end
