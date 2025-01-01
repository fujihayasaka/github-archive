# typed: true
# frozen_string_literal: true

class PurgeCancelledTrialsJob < ApplicationJob
  queue_as :purge_cancelled_trials
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 1.day, condition: -> { !GitHub.single_business_environment? }

  def perform
    Business.trial_cancelled.where("trial_completed_at < ?", Business::RESTORABLE_PERIOD.ago).each do |business|
      next if business.invoiced?

      business.organizations.each do |org|
        with_write do
          org.skip_admins_presence_validation = true
          org.async_destroy(User.ghost)
        end
      end
      DestroyBusinessJob.perform_later(business.id)
      GitHub.dogstats.increment("cancelled_trials_purged.count")
    end
  end
end
