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
    # user       - Delivery recipient User.
    # settings   - A Newsies::Settings object of the user receiving this
    #              notification.
    # event_time - Time of the notification generating event
    # reason     - (Optional) Symbol subscription reason for the user.
    # root_job_enqueued_at - Time the parent job was enqueued.
    #
    # Returns Newsies::Responses::Boolean instance.
    def deliver(delivery, user, settings, event_time:, reason: nil, root_job_enqueued_at: nil, priority: :high, extra_tags: [], inspector: nil, is_update: false, author: nil)
      return false unless deliver?(delivery.comment, user)

      force_deliver(delivery, user, event_time:, reason:, root_job_enqueued_at:, priority:, extra_tags:, inspector:, is_update:, author:)
    end

    # Internal: Delivers a web notification without checking if the delivery should actually be delivered.
    # This check is caller's responsibility.
    # This is only publicly available for internal use during notifications migration to notifyd,
    # it shouldn't be directly used otherwise.
    #
    # delivery   - A Newsies::Delivery.
    # user       - The User receiving this notification object of the user receiving this notification.
    # event_time - Time of the notification generating event
    # reason     - (Optional) Symbol subscription reason for the user.
    # root_job_enqueued_at - Time the parent job was enqueued.
    #
    # Returns Newsies::Responses::Boolean instance.
    def force_deliver(delivery, user, event_time:, reason: nil, root_job_enqueued_at: nil, priority: :high, extra_tags: [], inspector: nil, is_update: false, author: nil)
      Newsies::NotificationEntry.insert(
        user.id,
        delivery.summary,
        reason: reason,
        event_time: event_time,
      )

      user&.notify_web_notifications_changed_socket_subscribers(Newsies::NotificationEntry.default_live_updates_wait)

      GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:success", "handler:#{handler_key}"])

      DeliveryLogger.log_to_splunk_and_hydro(
        delivery,
        user: user,
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
    def deliver?(comment, user)
      # We do want to notify the author in actions notifications
      return true if actions_notification?(comment)
      return true unless comment.notifications_author

      is_author = comment.notifications_author.id == user.id
      if is_author
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["type:filter", "filter:is_author", "handler:#{handler_key}"])
      end
      !is_author
    end

    def actions_notification?(comment)
      comment.is_a?(CheckSuiteEventNotification) || comment.is_a?(GateRequest)
    end
  end
end
