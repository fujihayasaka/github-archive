# typed: strict
# frozen_string_literal: true

module Business::BillingContractUpdateDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  requires_ancestor { Business }

  CONTRACT_RENEWAL_WINDOW_LONG = T.let(90.days, ActiveSupport::Duration)
  CONTRACT_RENEWAL_WINDOW_SHORT = T.let(30.days, ActiveSupport::Duration)
  ANNUAL_TERM_LENGTH = T.let(12, Integer)
  LOCK_OUT_DURATION = T.let(7.days, ActiveSupport::Duration)

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

    scope :self_renewal_eligible, -> {
      joins(:customer)
      .where(customers: {
        billing_type: Customer::BILLING_TYPE_INVOICE,
        term_length: ANNUAL_TERM_LENGTH,
      })
      .where.not(customers: { zuora_account_id: nil })
      .not_trial
    }
    scope :with_term_end_date, ->(range) {
      joins(:customer).where(customers: { billing_end_date: range })
    }
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

  # Upgrades are locked out for 7 days before the renewal date
  sig { returns(T::Boolean) }
  def in_lock_out_period?
    return true if update_change_request&.items&.change_type_update&.any?(&:status_pending?)
    return false unless start_date = renewal_change_request&.items&.first&.start_date
    # Start date is expiry + 1 day, so subtract one more day
    return true if ((start_date - LOCK_OUT_DURATION - 1.day)..start_date).cover?(GitHub::Billing.today)
    !renewal_successful? && start_date <= GitHub::Billing.today
  end

  sig { returns(T::Boolean) }
  memoize def eligible_for_renewal?
    in_renewal_window? && !renewal_already_requested?
  end

  sig { returns(T::Boolean) }
  def eligible_for_upgrade?
    return false if GitHub::Billing.past?(self.billing_term_ends_on)
    return false if self.in_lock_out_period?

    # If it's outside the renewal window, we can always upgrade
    return true if !self.in_renewal_window?

    # If it's within the renewal window, we can upgrade if the renewal request has a seat gap
    self.renewal_already_requested? && self.renewal_has_seat_gap?
  end

  sig { params(short_window: T::Boolean).returns(T::Boolean) }
  def in_renewal_window?(short_window: false)
    # Non invoiced businesses do not have a renewal window as they are auto renewed
    return false unless invoiced?

    days = short_window ? CONTRACT_RENEWAL_WINDOW_SHORT : CONTRACT_RENEWAL_WINDOW_LONG
    ((GitHub::Billing.today - 1.year).next..(GitHub::Billing.today + days)).cover?(billing_term_ends_on)
  end

  sig { returns(T::Boolean) }
  def renewal_already_requested?
    change_requests = Billing::SalesServeSubscriptionChangeRequest.where(customer: customer)
    renewal_date = (billing_term_ends_on + 1.day).to_datetime
    change_requests.any? { |cr| cr.items.with_start_date(renewal_date).any? }
  end

  sig { returns(T::Boolean) }
  def has_contract_change?
    # Check the latest change request. If that needs to be shown, then we need to show the banner
    return false unless change_request = latest_change_request
    if change_request.items.change_type_renewal.present?
      # If there's a renewal, check that it hasn't started
      return false if change_request.items.change_type_renewal.all? { |item| item.status_complete? && item.start_date < self.billing_term_ends_on }
    else
      # If there's an upgrade, check that it's for today
      return false if change_request.items.change_type_update.all? { |item| item.status_complete? && GitHub::Billing.past?(item.start_date) }
    end

    true
  end

  sig { returns(T::Boolean) }
  def has_any_failed_ghe_change_requests?
    change_requests.any? do |cr|
      cr.failed? && cr.github_enterprise_change?
    end
  end

  sig { returns(T::Boolean) }
  def has_any_pending_ghe_change_requests?
    change_requests.any? do |cr|
      cr.pending? && cr.github_enterprise_change?
    end
  end

  sig { returns(T::Boolean) }
  def has_any_failed_renewal_requests?
    !!(renewal_change_request&.failed?)
  end

  sig { returns(T::Boolean) }
  def has_any_failed_ghas_change_requests?
    change_requests.any? do |cr|
      cr.failed? && cr.github_advanced_security_change?
    end
  end

  sig { returns(T::Boolean) }
  def has_any_pending_ghas_renewal_requests?
    !!(renewal_change_request&.pending? && renewal_change_request&.github_advanced_security_change?)
  end

  sig { returns(T::Boolean) }
  def has_any_pending_ghe_renewal_requests?
    !!(renewal_change_request&.pending? && renewal_change_request&.github_enterprise_change?)
  end

  sig { returns(T::Boolean) }
  def has_any_failed_update_requests?
    !!(update_change_request&.failed?)
  end

  sig { returns(T::Boolean) }
  def has_any_failed_change_requests?
    has_any_failed_update_requests? || has_any_failed_renewal_requests?
  end

  sig { returns(T::Boolean) }
  def has_any_pending_renewal_requests?
    !!(renewal_change_request&.pending?)
  end

  sig { returns(T::Boolean) }
  def has_any_pending_update_requests?
    !!(update_change_request&.pending?)
  end

  sig { returns(T::Boolean) }
  def has_any_pending_change_requests?
    has_any_pending_update_requests? || has_any_pending_renewal_requests?
  end

  sig { returns(T.nilable(Integer)) }
  memoize def ghas_update_seat_quantity_difference
    item = T.let(
      update_change_request&.items&.change_type_update&.github_advanced_security&.first,
      T.nilable(Billing::SalesServeSubscriptionChangeRequestItem),
    )
    return if item.nil?

    item.quantity.to_i - self.advanced_security_seats_for_entity
  end

  sig { returns(T.nilable(Integer)) }
  memoize def ghas_renewal_seat_quantity
    item = renewal_change_request&.items&.change_type_renewal&.github_advanced_security&.first
    return if item.nil?

    item.quantity.to_i
  end

  sig { returns(T.nilable(Integer)) }
  memoize def ghas_renewal_seat_quantity_difference
    return if ghas_renewal_seat_quantity.nil?

    T.must(ghas_renewal_seat_quantity) - self.advanced_security_seats_for_entity
  end

  sig { returns(Integer) }
  def update_seat_quantity_difference
    return 0 unless request = update_change_request
    request.items.change_type_update.first&.quantity.to_i - self.seats
  end

  sig { returns(T.nilable(Integer)) }
  memoize def ghe_renewal_seat_quantity
    item = renewal_change_request&.items&.change_type_renewal&.github_enterprise&.first
    return if item.nil?

    item.quantity.to_i
  end

  sig { returns(T.nilable(Integer)) }
  memoize def ghe_update_seat_quantity
    item = update_change_request&.items&.change_type_update&.github_enterprise&.first
    return if item.nil?

    item.quantity.to_i
  end

  sig { returns(T.nilable(Integer)) }
  memoize def ghe_renewal_seat_quantity_difference
    return if ghe_renewal_seat_quantity.nil?

    T.must(ghe_renewal_seat_quantity) - self.seats
  end

  sig { returns(T::Boolean) }
  memoize def renewal_has_seat_gap?
    renewal_has_ghas_seat_gap? || renewal_has_ghe_seat_gap?
  end

  sig { returns(T::Boolean) }
  memoize def ghe_renewal?
    !!renewal_change_request&.items&.change_type_renewal&.github_enterprise&.exists?
  end

  sig { returns(T::Boolean) }
  memoize def ghas_renewal?
    !!renewal_change_request&.items&.change_type_renewal&.github_advanced_security&.exists?
  end

  sig { returns(T::Boolean) }
  memoize def ghas_update?
    !!update_change_request&.items&.change_type_update&.github_advanced_security&.exists?
  end

  sig { returns(T::Boolean) }
  def renewal_successful?
    !!(renewal_change_request&.success?)
  end

  sig { returns(T::Boolean) }
  def update_successful?
    return false unless request = update_change_request
    request.items.change_type_update.all?(&:status_complete?)
  end

  sig { params(date: T.any(ActiveSupport::TimeWithZone, Time)).returns(T::Boolean) }
  def has_change_request_update_newer_than?(date)
    [update_change_request&.updated_at, renewal_change_request&.updated_at].compact.any? { |d| d.after?(date) }
  end

  sig { returns(T.nilable(Time)) }
  memoize def renewal_scheduled_start_datetime
    renewal_change_request&.items&.change_type_renewal&.first&.start_date
  end

  sig { returns(T.nilable(Time)) }
  memoize def update_scheduled_start_datetime
    update_change_request&.items&.change_type_update&.first&.start_date
  end

  sig { returns(T.nilable(Billing::SalesServeSubscriptionChangeRequest)) }
  memoize def update_change_request
    # Update can only happen on the last change request
    return nil unless change_request = latest_change_request
    change_request if change_request.items.change_type_update.any?
  end

  sig { returns(T.nilable(Billing::SalesServeSubscriptionChangeRequest)) }
  memoize def renewal_change_request
    return nil unless change_request = latest_change_request
    return change_request if change_request.items.change_type_renewal.any?

    # If the latest change request is only update, then we need to check if there is a renewal in the previous change request
    # If the renewal has a start date before any updates, it's a past renewal and we don't want that.
    reference_date = change_request.items.first&.start_date
    change_requests.find do |cr|
      cr.items.change_type_renewal.with_start_date(reference_date..).any?
    end
  end

  sig { returns(T::Boolean) }
  memoize def renewal_has_ghas_seat_gap?
    return false if update_change_request&.items&.change_type_update&.github_advanced_security&.not_status_error.present?
    return false unless difference = ghas_renewal_seat_quantity_difference

    difference > 0
  end

  sig { returns(T::Boolean) }
  memoize def renewal_has_ghe_seat_gap?
    return false if update_change_request&.items&.change_type_update&.github_enterprise&.not_status_error.present?
    return false unless difference = ghe_renewal_seat_quantity_difference

    difference > 0
  end

  private

  sig { returns(T::Array[Billing::SalesServeSubscriptionChangeRequest]) }
  memoize def change_requests
    # Add a buffer to show the status after the renewal window has closed
    duration = CONTRACT_RENEWAL_WINDOW_LONG + 1.day
    Billing::SalesServeSubscriptionChangeRequest
      .where(customer: customer)
      .where(created_at: duration.ago..)
      .order(created_at: :desc)
      .to_a
  end

  sig { returns(T.nilable(Billing::SalesServeSubscriptionChangeRequest)) }
  def latest_change_request
    change_requests.first
  end

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
