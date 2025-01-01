# typed: true
# frozen_string_literal: true

module Newsies
  class SpammyNotificationEntry < ApplicationRecord::Domain::NotificationsEntries
    self.utc_datetime_columns = [:updated_at, :last_read_at]
    self.record_timestamps = false

    enum :unread, {
      inbox_read: 0,
      inbox_unread: 1,
      archived: 2
    }

    scope :for_thread, ->(thread) {
      raise ArgumentError, "thread cannot be nil" unless thread
      where(
        list_type: thread.list_type,
        list_id: thread.list_id,
        thread_key: thread.list_id_key,
      )
    }
  end
end
