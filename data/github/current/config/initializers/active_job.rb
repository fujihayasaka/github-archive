# frozen_string_literal: true

require "serializers/stratocaster_event"
require "serializers/usage_notification_content"
require "serializers/turboghas_sku"
require "serializers/sendgrid_data"

Rails.application.config.active_job.custom_serializers += [
  Serializers::StratocasterEvent,
  Serializers::UsageNotificationContent,
  Serializers::TurboghasSKU,
  Serializers::SendgridData,
]

module ActiveJob
  module QueueAdapters
    class TestAdapter
      def peek(queue:, limit:)
        enqueued_jobs
          .map { |serialized| ActiveJob::Base.deserialize(serialized) }
          .select { |job| job.queue_name == queue }
          .each { |job| job.send(:deserialize_arguments_if_needed) }
          .take(limit)
      end

      def queue_depth(queue:)
        enqueued_jobs.count { |job| job["queue_name"] == queue }
      end
    end
  end
end
