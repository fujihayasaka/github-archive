# typed: false
# frozen_string_literal: true

module Newsies
  # Marks notifications as read for a given user and optional list that haven't been
  # updated since a given time
  class MarkAllNotificationsAsReadJob < ApplicationJob
    include ActiveJob::InitiallyEnqueuedAt

    queue_as :notifications

    retry_on_dirty_exit

    # batch size for iterating the notifications in the job to ensure we throttle queries appropriately
    BATCH_SIZE = 50

    FIVE_MINUTES = 300000

    retry_on_recoverable_exceptions

    # Override this in your job if you'd like to include custom tags
    def stats_tags
      ["list_type:#{arguments.third}"]
    end

    # user_id         - Integer user id
    # last_read_at    - DateTime when notifications have been read the last time
    #                  (prevents us from accidentally marking newer things as read).
    # list_type       - Optional: String newsies list type
    # list_id         - Optional: Integer newsies list id
    def perform(user_id, last_read_at, list_type = nil, list_id = nil)
      time_since_enqueued_ms = (Time.now.utc.to_f - initially_enqueued_at.to_f) * 1000
      unless time_since_enqueued_ms < FIVE_MINUTES
        GitHub.dogstats.increment("job.mark_all_notifications_as_read.skip_job")
        return
      end

      unless (list_type.nil? && list_id.nil?) || (list_type.present? && list_id.present?)
        raise ArgumentError, "list_type and list_id both need to be nil or provided"
      end
      return unless user = User.find_by_id(user_id)

      list = List.new(list_type, list_id) if list_type && list_id

      notifications = NotificationEntry.unread_before(last_read_at, user_id, list)
      trace_attributes = {
        "gh.user.id" => user_id,
        "gh.notifications.job.item.count" => notifications.size,
        "gh.notifications.list.id" => list_id,
        "gh.notifications.list.type" => list_type
      }.compact

      GitHub.tracer.in_span("update_all", kind: :internal, attributes: trace_attributes) do
        notifications.in_batches(of: BATCH_SIZE) do |scope|
          NotificationEntry.throttle_writes do
            scope.update_all(unread: Newsies::NotificationEntry.statuses[:inbox_read], last_read_at: last_read_at)
          end
        end
      end
      nil
    end
  end
end
