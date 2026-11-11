# typed: strict
# frozen_string_literal: true

module Billing::MeteredBillable
  extend T::Helpers

  extend ActiveSupport::Concern

  NO_BUDGET_PRODUCTS = T.let(["copilot"], T::Array[String])

  requires_ancestor { ActiveRecord::Base }
  requires_ancestor { Kernel }

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))

    has_many :budgets,
      class_name: "Billing::Budget",
      dependent: :destroy,
      as: :owner
  end

  sig { returns(Integer) }
  def customer_bill_cycle_day
    T.bind(self, Billing::Types::Account)
    return business.customer_bill_cycle_day if delegate_billing_to_business?

    if billed_through_azure_subscription?
      1
    else
      customer&.bill_cycle_day.to_i
    end
  end

  sig { returns(Integer) }
  def metered_cycle_day
    T.bind(self, Billing::Types::Account)
    return 1 if metered_via_azure?

    [customer_bill_cycle_day.to_i, 1].max
  end

  # Metered accounts billed on billing platform are cycled through 1st to end of month
  sig { returns(ActiveSupport::TimeWithZone) }
  def current_metered_billing_cycle_starts_at
    T.bind(self, Billing::Types::Account)
    return business.current_metered_billing_cycle_starts_at if delegate_billing_to_business?

    Time.now.utc.beginning_of_month.in_time_zone("UTC")
  end

  sig { returns(ActiveSupport::TimeWithZone) }
  def next_metered_billing_cycle_starts_at
    T.bind(self, Billing::Types::Account)
    return business.next_metered_billing_cycle_starts_at if delegate_billing_to_business?

    (current_metered_billing_cycle_starts_at + 1.month).in_time_zone("UTC")
  end

  sig { params(product: T.nilable(T.any(String, Symbol)), group: T.nilable(T.any(String, Symbol))).returns(T::Boolean) }
  def metered_billing_overage_allowed?(product: nil, group: nil)
    T.bind(self, ::Billing::Types::Account)

    if try(:has_any_trade_restrictions?) || (billed_through_azure_subscription? && !linked_azure_subscription?)
      return false
    end

    relation = budgets.overage_allowed
    if group
      relation = relation.where(product: group)
    elsif product
      relation = relation.where(product: Billing::Budget.budget_group_for(product: product, prepaid: false))
    end

    relation.exists?
  end

  sig do
    params(
      product: T.nilable(T.any(String, Symbol)),
      group: T.nilable(T.any(String, Symbol)),
      budget_name: T.nilable(String),
      business: T.nilable(Business)
    ).returns(::Billing::Budget)
  end
  def budget_for(product: nil, group: nil, budget_name: nil, business: nil)
    T.bind(self, ::Billing::Types::Account)
    raise ArgumentError, "Expected either product or group to be present" if product.nil? && group.nil?

    if NO_BUDGET_PRODUCTS.include?(product)
      log_zero_budget(product: product, reason: "unsupported_product")
      return budgets.new(enforce_spending_limit: false, spending_limit_in_subunits: 0)
    end

    product_key = group.presence || budget_group_for(product: T.must(product))
    # group could also be a passed in as a symbol causing product_key to be a symbol
    product_key = product_key.to_s

    raise ArgumentError, "Invalid budget group #{product_key}" unless Billing::Budget.valid_budget_group?(product_key)
    if try(:has_any_trade_restrictions?) || (billed_through_azure_subscription? && !linked_azure_subscription?)
      log_zero_budget(product: product_key, reason: "account with trade restrictions or missing Azure subcription")
      Billing::Budget.new(owner: self, enforce_spending_limit: true, spending_limit_in_subunits: 0, product: product_key, budget_name: budget_name).tap(&:readonly!)
    else
      existing_budget = budgets.find_by(product: product_key)
      return existing_budget if existing_budget.present?

      # all codespaces default budgets should be set at 0
      if !FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, business) && product_key == "codespaces" # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        log_zero_budget(product: product_key, reason: "codespaces")
        return budgets.build(product: product_key, enforce_spending_limit: true, spending_limit_in_subunits: 0)
      end

      # default budget(s)
      if invoiced? && !billed_through_azure_subscription?
        if FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, business) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          budgets.build(product: product_key, enforce_spending_limit: false, budget_name: budget_name)
        else
          budgets.build(product: product_key, enforce_spending_limit: false)
        end
      else
        if FeatureFlag.vexi.enabled_or_raise?(:ghe_spending_limits, business) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          budgets.build(product: product_key, budget_name: budget_name)
        else
          budgets.build(product: product_key)
        end
      end
    end
  end

  sig { params(product: T.nilable(T.any(String, Symbol))).returns(T.nilable(String)) }
  def budget_group_for(product:)
    prepaid = Billing::PrepaidMeteredUsageRefill.enabled_for?(self)
    Billing::Budget.budget_group_for(product: product, prepaid: prepaid)
  end

  # Internal: This method will override the quota usage checks for this user until their next metered cycle.
  #
  # Only use this method if you exhausted all other possible ways to unblock the user.
  # The method was created to unblock users who are hitting the timeout issue due to too many line items for downloads
  # This will not only stop checking for quota usages during permission checks but also stop recording usage for the user
  #
  # product - One of the three metered billing products `actions`, `packages`, `storage`
  #
  sig { params(product: T.any(String, Symbol), expires: T.nilable(T.any(Time, Date, DateTime))).void }
  def skip_metered_billing_permission_check_for(product:, expires: nil)
    T.bind(self, ::Billing::Types::Account)
    expires ||= next_metered_billing_cycle_starts_at
    Billing::Kv.store.set(skip_metered_billing_permissions_key(product), "true", expires: expires)
  end

  sig { params(product: T.any(String, Symbol)).returns(T::Boolean) }
  def skip_metered_billing_permission_check_for?(product:)
    Billing::Kv.store.exists(skip_metered_billing_permissions_key(product)).value!
  end

  # Internal: This method will be used to prevent metered billable services from passing permission checks.
  #
  # We already have a billing lock on user which is more of a global lock and prevents other services from being used
  # but we need this more granular lock for metered services
  sig { void }
  def lock_metered_services
    clear_metered_services_locked_memoization

    Billing::Kv.store.set(metered_services_lock_key, "true")
    sync_with_billing_platform
  end

  # Internal: This method will be used to allow metered billable services.
  #
  # We already have a billing lock on user which is more of a global lock and prevents other services from being used
  # but we need this more granular lock for metered services
  sig { void }
  def unlock_metered_services
    clear_metered_services_locked_memoization

    Billing::Kv.store.del(metered_services_lock_key)
    sync_with_billing_platform
  end

  # Internal: This method will be used to query whether the metered billable services are enabled for the account.
  sig { returns(T::Boolean) }
  def metered_services_locked?
    return !!@metered_services_lock_key_value if defined?(@metered_services_lock_key_value)

    !!(@metered_services_lock_key_value = T.let(Billing::Kv.store.get(metered_services_lock_key).value { false } == "true", T.nilable(T::Boolean)))
  end

  sig { void }
  def clear_metered_services_locked_memoization
    remove_instance_variable(:@metered_services_lock_key_value) if defined?(@metered_services_lock_key_value)
  end

  MeteredServicesBillableResult = T.type_alias do
    {
      billable: T.nilable(T::Boolean),
      reason: Symbol,
    }
  end

  sig { void }
  def sync_with_billing_platform
    T.bind(self, ::Billing::Types::Account)
    customer = billable_owner.customer
    return unless customer.present?
    Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
  end

  sig { params(commercial_restriction_feature_type: T.any(String, Symbol), timeout: T.nilable(T.any(Integer, Float))).returns(MeteredServicesBillableResult) }
  def metered_services_billable?(commercial_restriction_feature_type: :default, timeout: nil)
    T.bind(self, ::Billing::Types::Account)
    with_database_error_fallback(fallback: { billable: nil, reason: :error }) do
      # There is only one SKU for individual accounts, which is copilot_premium_request, so that's the default for now
      product_sku_name = "copilot_premium_request"
      if billable_owner.business? || billable_owner.organization?
        emission_information = ::Copilot::Billing::Emittable.new(T.cast(billable_owner, ::Billing::Types::OrgOrBusiness))
        product_sku_name = emission_information.product_sku_name
      end

      if billable_owner.feature_flag_enabled?(:skip_cpwu_on_new_customer, default: false) && billable_owner.billing_customer.nil?
        billable_owner.find_or_create_customer
        return { billable: false, reason: :new_customer }
      end

      request_params = ::Billing::Platform::CanProceedWithUsage::RequestParams.new(
        customer_id: billable_owner.find_or_create_customer.id,
        product: "copilot",
        sku: product_sku_name
      )
      response = Billing::Platform::CanProceedWithUsage.call(request_params, timeout: timeout)
      if response.error.is_a?(Billing::Platform::Api::Error)
        { billable: nil, reason: response.status }
      else
        { billable: response.can_proceed, reason: response.status }
      end
    end
  end

  private

  sig { returns(String) }
  def metered_services_lock_key
    "metered-services-lock-#{self.class.name}-#{id}"
  end

  sig { params(product: T.any(String, Symbol)).returns(String) }
  def skip_metered_billing_permissions_key(product)
    "skip-metered-check-#{self.class.name}-#{id}-#{product}"
  end

  sig { params(reason: String, product: T.nilable(T.any(String, Symbol))).void }
  def log_zero_budget(reason:, product: "")
    T.bind(self, Billing::Types::Account)
    GitHub.logger.info("Returning $0 budget for #{reason}",
      "code.namespace" => self.class.name,
      "code.function" => "budget_for",
      "gh.billing.billable_entity.id" => billable_owner.id,
      "gh.billing.billable_entity.login" => billable_owner.display_login,
      "gh.product.name" => product,
    )
  end
end
