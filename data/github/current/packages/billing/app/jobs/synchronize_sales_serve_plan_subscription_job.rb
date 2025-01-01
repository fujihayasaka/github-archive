# typed: strict
# frozen_string_literal: true

class SynchronizeSalesServePlanSubscriptionJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :synchronize_sales_serve_plan_subscription
  locked_by timeout: 30.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SynchronizeSalesServePlanSubscriptionJob)

    zuora_rate_limit_handler(self, error)
  end

  sig { params(business: T.nilable(Business)).void }
  def perform(business:)
    return unless business
    return unless business.feature_enabled?(:queue_job_for_sales_managed_subscription_sync)
    return unless sales_managed_subscription = business.sales_managed_subscription

    # DB backed plan subscription record
    if plan_subscription = business.sales_serve_plan_subscription
      return unless plan_subscription.self_serve_eligible?
      # List out all the things we care about, if any of them are missing, proceed with syncing
      return if plan_subscription.ghe_rate_plan_charge
    end

    with_write do
      Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(sales_managed_subscription).sync
    end
  end
end
