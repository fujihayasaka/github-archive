# typed: true
# frozen_string_literal: true

class BillingRunStartJob < BillingJob
  exempt_from_tenant_context_requirement

  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  def perform
    now = GitHub::Billing.now
    # We only want to run this job once per day between 4am and 5am Pacific time.
    if now.hour >= 4 && now.hour < 5
      # Expire stale coupon redemptions before the billing run starts.
      # Doing this ensures that accounts with a stale coupon are downgraded instead of dunned.
      # If we don't do this, a large number of accounts (e.g. those with a student coupon)
      # will be dunned and customers will write in asking why we tried to charge them.
      with_write { CouponRedemption.expire! }

      # Fan out to self-re-enqueueing batched jobs. Each processes one batch
      # per invocation and re-enqueues itself, avoiding long-running queries.
      # max_id is computed once here and propagated through all re-enqueues
      # so each invocation doesn't need to re-query MAX(id).
      business_max_id, user_max_id = ActiveRecord::Base.connected_to(role: :reading) do
        [
          CustomerAccount.where(billable_entity_type: "Business").order(id: :desc).pick(:id).to_i,
          User.order(id: :desc).pick(:id).to_i,
        ]
      end
      DebtHunterBusinessBatchedJob.perform_later(max_id: business_max_id)
      DebtHunterUserBatchedJob.perform_later(max_id: user_max_id)

      GitHub.dogstats.timing("billing_run_start_job.time", GitHub::Dogstats.duration(now))
    end
  end
end
