# typed: false
# frozen_string_literal: true

module Newsies
  class DeliveryLogger
    extend SloHelper

    # Mapping of (inclusive) upper bound on time_to_sent_ms to a bucket name
    TIME_TO_SENT_BUCKETS_MS = [
      # upper bound ms, tag name
      [1.second.in_milliseconds,   "bucket:0s-1s"],
      [5.seconds.in_milliseconds,  "bucket:1s-5s"],
      [30.seconds.in_milliseconds, "bucket:5s-30s"],
      [1.minute.in_milliseconds,   "bucket:30s-1m"],
      [3.minutes.in_milliseconds,  "bucket:1m-3m"],
      [5.minutes.in_milliseconds,  "bucket:3m-5m"],
      [10.minutes.in_milliseconds, "bucket:5m-10m"],
      [Float::INFINITY,            "bucket:10m-plus"],
    ]

    def self.log_to_datadog(handler_key:, event_time:, extra_tags: [])
      return unless event_time.present?
      time_to_sent_ms = (Time.now.utc.to_f - event_time.to_f) * 1000.0

      GitHub.dogstats.timing("newsies.delivery.time_to_sent", time_to_sent_ms, tags: [
        "handler:#{handler_key}",
        slo_bucket_tag(TIME_TO_SENT_BUCKETS_MS, time_to_sent_ms),
        *extra_tags
      ])
    end

    # Public: Logs a delivery to splunk and hydro.
    #
    # delivery               - An instance of Newsies::Delivery.
    # user                   - A User object.
    # reason                 - String specifying the reason the user received a notification.
    # handler_key            - Key specifying the handler.
    # event_time             - Time at which the notified event was created
    # root_job_enqueued_at   - Integer or Float epoch timestamp for when the first notification
    #                          delivery job for the content in question was enqueued. Note that since this job may be a
    #                          dependent of other delivery jobs, this might be the time at which an ancestor job was
    #                          enqueued.
    # additional_splunk_data - Additional key/value(s) to log to splunk.
    #
    # Returns nothing.
    def self.log_to_splunk_and_hydro(delivery, user:, reason:, handler_key:, event_time:, root_job_enqueued_at:, **additional_splunk_data)
      log_to_splunk(
        delivery,
        user: user,
        reason: reason,
        handler_key: handler_key,
        event_time: event_time,
        root_job_enqueued_at: root_job_enqueued_at,
        **additional_splunk_data,
      )

      log_to_hydro(delivery, user: user, reason: reason, handler_key: handler_key)
    end

    def self.log_to_hydro(delivery, user:, reason:, handler_key:)
      GlobalInstrumenter.instrument("notifications.delivery",
        user: user,
        handler: handler_key,
        list_type: delivery.list_type,
        list_id: delivery.list_id,
        thread_type: delivery.thread_type,
        thread_id: delivery.thread_id,
        comment_type: delivery.comment_type,
        comment_id: delivery.comment_id,
        notification_id: delivery.notification_id,
        reason: reason.to_s,
      )
    end

    def self.log_to_splunk(delivery, user:, reason:, handler_key:, event_time:, root_job_enqueued_at:, **additional)
      delivered_at_time = Time.now.to_f

      log_hash = {
        "gh.notifications.delivery.list.type" => delivery.list_type,
        "gh.notifications.delivery.list.id" => delivery.list_id,
        "gh.notifications.delivery.thread.type" => delivery.thread_type,
        "gh.notifications.delivery.thread.id" => delivery.thread_id,
        "gh.notifications.delivery.comment.type" => delivery.comment_type,
        "gh.notifications.delivery.comment.id" => delivery.comment_id,
        "gh.notifications.delivery.notification.id" => delivery.notification_id,
        "gh.notifications.handler" => handler_key,
        "gh.notifications.reason" => reason.to_s,
        "gh.notifications.recipient.login" => user.login, # rubocop:disable GitHub/DoNotAllowLogin login is ok when used for logging
        "gh.notifications.recipient.id" => user.id,
        "gh.job.enqueued_at" => root_job_enqueued_at,
        "gh.notifications.delivered_at" => delivered_at_time,
        "gh.notifications.time_to_sent" => event_time.present? ? delivered_at_time - event_time.to_f : nil,
        "gh.notifications.delivery.additional" => additional,
        "gh.user.id" => user.id,
      }

      GitHub.logger.info("notification delivered", log_hash)
    end
  end
end
