# typed: strict
# frozen_string_literal: true

module Business::BillingContractUpdateDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Business }

  SKU_LIST_PRICE_MAPPING = T.let({
    "2c92a00d6c755af5016c77f0287267c8" => 252, # GHE - Non-Profit
    "2c92a0ff67cebd0d0167e839eb127dcc" => 252, # GHE
    "2c92a0086477ed3301648681763e3631" => 250, # GHEC - Non-Profit
    "2c92a0fe6d8c63f6016db26c619a11cc" => 250, # GHEC
    "2c92a00d6d4dcd59016d609dd91b746e" => 588, # GHAS - Non-Profit
    "2c92a00d6ff0e96f016ff798507d58c8" => 588, # GHAS
    "2c92c0f96d05b076016d08f12ea8062a" => 252, # GHE - dev
    "2c92c0f86d4247e8016d4627a9337e41" => 588, # GHAS - dev
  }, T::Hash[String, Integer])

  sig { params(sku: String).returns(T.nilable(Integer)) }
  def self.list_price_for_sku(sku)
    SKU_LIST_PRICE_MAPPING[sku]
  end

  included do
    T.bind(self, T.class_of(Business))
  end

  sig { returns(T.nilable(Billing::Zuora::SalesManagedSubscription)) }
  def sales_managed_subscription
    with_error_fallback(fallback: nil, allowed_error_types: [Faraday::TimeoutError, Zuorest::TooManyRequestsError]) do
      return @sales_managed_subscription if defined?(@sales_managed_subscription)
      return @sales_managed_subscription = nil unless subscription_id = sales_serve_plan_subscription&.zuora_subscription_id
      @sales_managed_subscription ||= T.let(Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(subscription_id), T.nilable(Billing::Zuora::SalesManagedSubscription))
    end.value
  end

  sig { returns(T.nilable(Billing::SalesServePlanSubscription)) }
  def experiment_sales_managed_subscription
    subscription = customer&.sales_serve_plan_subscription
    ensure_sales_managed_subscription_is_populated(subscription)
    subscription
  end

  sig { returns(T::Boolean) }
  def sales_managed_subscription_self_serve_eligible?
    return true if self.feature_flag_enabled_or_raise?(:sales_managed_subscription_self_serve_eligible_override) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    if FeatureFlag.vexi.enabled?(:sales_serve_subscription_optimize_scientist, default: false)
      !!(experiment_sales_managed_subscription&.self_serve_eligible? && experiment_sales_managed_subscription&.ghe_rate_plan_charge.present?)
    else
      !!(sales_managed_subscription&.self_serve_eligible? && sales_managed_subscription&.ghe_rate_plan_charge.present?)
    end
  end

  private

  # In some rare occasions, the zuora rate plan charges off sales managed subscription
  # is not populated. Queue a job to populate it.
  sig { params(subscription: T.nilable(Billing::SalesServePlanSubscription)).void }
  def ensure_sales_managed_subscription_is_populated(subscription)
    if subscription
      return unless subscription.self_serve_eligible?
      return if subscription.ghe_rate_plan_charge
    end
    return unless self.feature_flag_enabled_or_raise?(:queue_job_for_sales_managed_subscription_sync) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    SynchronizeSalesServePlanSubscriptionJob.perform_later(business: T.bind(self, Business))
  end
end
