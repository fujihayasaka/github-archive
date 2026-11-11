# typed: strict
# frozen_string_literal: true

class RunPendingPlanChangeJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  discard_on ActiveJob::DeserializationError

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, RunPendingPlanChangeJob)

    zuora_rate_limit_handler(self, error)
  end

  MAX_WAIT_TIME = T.let(30 * 60, Integer) # i.e. 30mins

  sig { params(pending_plan_change: Billing::PendingPlanChange).void }
  def perform(pending_plan_change)
    active_on = pending_plan_change.active_on
    if active_on > GitHub::Billing.today
      GitHub.dogstats.increment("scheduled_plan_change_corrected")

      # Note, active_on is a Date, so when we call to_time on it, it will be midnight of that day in PT.
      # Also, we run the job here at a random time between 12:00am and 12:30am PT to avoid db pressure/spikes.
      wait_until = active_on.to_time + rand(0..MAX_WAIT_TIME).seconds

      RunPendingPlanChangeJob
        .set(wait_until: wait_until)
        .perform_later(pending_plan_change)

      return
    end

    if pending_plan_change.incomplete?
      with_write { pending_plan_change.run }
    end
  end
end
