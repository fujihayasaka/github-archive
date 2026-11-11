# typed: true
# frozen_string_literal: true

require "github/config/kv_cleaner"

# Cleans up notification key-value entries whose expiry date has passed. Uses
# GitHub::Config::KVCleaner with a configurable batch size (default 100) and duration
# limit (default 60 seconds). Self-perpetuating: reschedules itself if cleanup isn't
# completed within the duration limit.
#
# Enqueued by: 6-hour interval schedule configured in config/timers.fe.rb,
# config/timers.enterprise.rb, and config/timers.proxima.rb.
class DeleteExpiredNotificationsKeyValuesJob < ApplicationJob
  # this interval is currently purely arbitrary. After we've watched this job
  # perform for a while we can use the gathered data to make an informed
  # decision how often to run it. The long delay between run times here is
  # also the reason why we mostly emit logs from this job and no datadog
  # metrics as they likely would be too sparse to be helpful
  schedule interval: 6.hours
  queue_as :notifications_maintenance
  retry_on_dirty_exit

  # This job iterates over expired key values without using a single tenant
  exempt_from_tenant_context_requirement

  use_replicas ApplicationRecord::Mysql1, ApplicationRecord::Mysql2

  class NotificationKeyValue < ApplicationRecord::Domain::Notifications
    self.table_name = "notification_key_values"
  end

  sig { params(batch_size: Integer, duration: Integer).void }
  def perform(batch_size: 100, duration: 60)
    GitHub.logger.info("running cleanup job", {
      "code.namespace" => "DeleteExpiredNotificationsKeyValuesJob",
      "batch_size" => batch_size,
      "duration" => duration,
    })

    # initialize result with bogus data and the right type
    result = GitHub::Config::KVCleaner::Result.new(batch_count: 0,
                                                   deleted_key_count: 0,
                                                   status: :nil,
                                                   job_duration: 0)
    GitHub.tracer.in_span("cleanup_expired_keys", kind: :internal) do
      cleaner = GitHub::Config::KVCleaner.new(model_class: NotificationKeyValue)
      result = cleaner.cleanup_expired_keys(max_duration: duration.seconds)
    end

    # if we didn't finish, schedule another job to continue the cleanup
    unless result.completed?
      GitHub.logger.info("cleanup run not completed, scheduling another job to continue", {
        "code.namespace" => "DeleteExpiredNotificationsKeyValuesJob",
        "status" => result.status,
        "deleted_keys" => result.deleted_key_count,
        "batch_size" => batch_size,
        "duration" => duration,
      })
      self.class.perform_later(batch_size: batch_size, duration: duration)
      return
    end

    GitHub.logger.info("cleanup run completed", {
      "code.namespace" => "DeleteExpiredNotificationsKeyValuesJob",
      "status" => result.status,
      "deleted_keys" => result.deleted_key_count
    })
  end
end
