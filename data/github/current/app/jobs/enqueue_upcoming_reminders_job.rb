# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class EnqueueUpcomingRemindersJob < ApplicationJob
  queue_as :low # rubocop:todo GitHub/DoNotUseGenericBackgroundJobQueues

  schedule interval: 10.minutes

  # There's no need to run this job in the context of a tenant, since it's just
  # iterates over all upcoming reminders on the stamp and enqueues a job for each
  # the job it enqueue is tenant aware (see resolve_tenant_context in process_reminder_job.rb)
  exempt_from_tenant_context_requirement

  def perform
    ReminderDeliveryTime.upcoming.find_each do |delivery_time|
      delivery_target = delivery_time.next_delivery_at

      if FeatureFlag.vexi.enabled?(:precompute_process_reminders, delivery_time.schedulable.user, default: false)
        # perform the job a bit earlier than the notification delivery
        # to avoid straining the DB. the notifications are still delivered at delivery_target
        # but their content is prepared in advance
        wait_until = delivery_target - SecureRandom.rand(5..90).seconds
      else
        wait_until = delivery_target
      end

      ProcessReminderJob.set(wait_until: wait_until).perform_later(delivery_time.schedulable, delivery_target: delivery_target)
    end
  end
end
