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
      if !GitHub.flipper[:ghe_spending_limits].enabled?(business) && product_key == "codespaces"
        log_zero_budget(product: product_key, reason: "codespaces")
        return budgets.build(product: product_key, enforce_spending_limit: true, spending_limit_in_subunits: 0)
      end

      # default budget(s)
      if invoiced? && !billed_through_azure_subscription?
        if GitHub.flipper[:ghe_spending_limits].enabled?(business)
          budgets.build(product: product_key, enforce_spending_limit: false, budget_name: budget_name)
        else
          budgets.build(product: product_key, enforce_spending_limit: false)
        end
      else
        if GitHub.flipper[:ghe_spending_limits].enabled?(business)
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
    Billing::Kv.store.exists(skip_metered_billing_permissions_key(product)).value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  # Internal: This method will be used to prevent metered billable services from passing permission checks.
  #
  # We already have a billing lock on user which is more of a global lock and prevents other services from being used
  # but we need this more granular lock for metered services
  sig { void }
  def lock_metered_services
    clear_metered_services_locked_memoization

    Billing::Kv.store.set(metered_services_lock_key, "true")
  end

  # Internal: This method will be used to allow metered billable services.
  #
  # We already have a billing lock on user which is more of a global lock and prevents other services from being used
  # but we need this more granular lock for metered services
  sig { void }
  def unlock_metered_services
    clear_metered_services_locked_memoization

    Billing::Kv.store.del(metered_services_lock_key)
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
      billable: T::Boolean,
      reason: Symbol,
    }
  end

  sig { params(commercial_restriction_feature_type: T.any(String, Symbol)).returns(MeteredServicesBillableResult) }
  def metered_services_billable?(commercial_restriction_feature_type: :default)
    T.bind(self, ::Billing::Types::Account)
    GitHub.logger.with_named_tags(
      "code.function" => "metered_services_billable?",
      "code.namespace" => self.class.name,
      "gh.billing.commercial_restriction_feature_type" => commercial_restriction_feature_type,
      "gh.billing.account.id" => billable_owner.id,
      "gh.billing.account.type" => billable_owner.class.name,
    ) do
      # if the billable owner is disabled, block them
      if billable_owner.disabled?
        GitHub.logger.info("Billable owner is disabled", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:disabled"])
        return { billable: false, reason: :disabled }
      end

      if billable_owner.metered_services_locked?
        GitHub.logger.info("Billable owner is metered services locked", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:metered_services_locked"])
        return { billable: false, reason: :metered_services_locked }
      end

      if billable_owner.suspended?
        GitHub.logger.info("Billable owner is suspended", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:suspended"])
        return { billable: false, reason: :suspended }
      end

      # Trade restrictions
      if billable_owner.has_full_trade_restrictions?
        GitHub.logger.info("Billable owner has full trade restrictions", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:has_full_trade_restrictions"])
        return { billable: false, reason: :has_full_trade_restrictions }
      end

      if billable_owner.has_any_trade_restrictions?
        GitHub.logger.info("Billable owner has trade restrictions", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:has_any_trade_restrictions"])
        return { billable: false, reason: :has_any_trade_restrictions }
      end

      # Accounts (invoiced or self-serve) that are metered through Azure need to have an Azure Subscription ID
      if billable_owner.customer&.requires_azure_subscription?
        if billable_owner.customer&.azure_subscription_id.present?
          GitHub.logger.info("Billable owner is metered through Azure with a subscription id", "gh.billing.metered_services_billable" => true)
          GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:true", "reason:azure_subscription_id"])
          return { billable: true, reason: :azure_subscription_id }
        else
          GitHub.logger.info("Billable owner is metered through Azure with no subscription id", "gh.billing.metered_services_billable" => false)
          GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:metered_through_azure_with_no_azure_subscription_id"])
          return { billable: false, reason: :metered_through_azure_with_no_azure_subscription_id }
        end
      end

      strict_zuora_validation =
        billable_owner.feature_enabled?(:strict_zuora_validation_on_metered_billable_check) ||
        !billable_owner.invoiced?

      # Accounts that are not metered through Azure must have a Zuora account and Zuora subscription
      unless billable_owner.customer&.zuora?
        GitHub.logger.info("Billable owner is not metered through Azure but does not have a zuora account", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:non_azure_no_zuora_account"])
        if strict_zuora_validation
          return { billable: false, reason: :non_azure_no_zuora_account }
        else
          GitHub.logger.info("Skipping zuora account validation for metered billing")
          GitHub.dogstats.increment("billing.metered_services_billable", tags: ["reason:skipped_zuora_account_validation"])
        end
      end

      unless billable_owner.active_plan_subscription&.zuora_subscription_number.present?
        GitHub.logger.info("Billable owner is not metered through Azure, has a zuora account but no subscription", "gh.billing.metered_services_billable" => false)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:non_azure_no_zuora_subscription"])
        if strict_zuora_validation
          return { billable: false, reason: :non_azure_no_zuora_subscription }
        else
          GitHub.logger.info("Skipping zuora subscription validation for metered billing")
          GitHub.dogstats.increment("billing.metered_services_billable", tags: ["reason:skipped_zuora_subscription_validation"])
        end
      end

      # Accounts that are metered through Zuora must be invoiced or have a valid payment method (self-serve)
      if billable_owner.invoiced?
        GitHub.logger.info("Billable owner is metered through zuora and invoiced", "gh.billing.metered_services_billable" => true)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:true", "reason:zuora_invoiced_subscription"])
        return { billable: true, reason: :zuora_invoiced_subscription }
      end

      if !!billable_owner.payment_method&.valid_payment_token?
        GitHub.logger.info("Billable owner is metered through zuora and has a valid payment method", "gh.billing.metered_services_billable" => true)
        GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:true", "reason:zuora_valid_payment_method"])
        return { billable: true, reason: :zuora_valid_payment_method }
      end

      GitHub.logger.info("Billable owner is not metered_services_billable for unknown reasons", "gh.billing.metered_services_billable" => false)
      GitHub.dogstats.increment("billing.metered_services_billable", tags: ["billable:false", "reason:unknown"])
      { billable: false, reason: :unknown }
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
