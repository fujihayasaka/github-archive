# typed: strict
# frozen_string_literal: true

module Billing::MeteredBillable
  include Scientist
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
      billable: T::Boolean,
      reason: Symbol,
    }
  end

  ExperimentMeteredServicesBillableResult = T.type_alias do
    {
      cpwu: T.nilable(MeteredServicesBillableResult),
      legacy: T.nilable(MeteredServicesBillableResult)
    }
  end

  sig { void }
  def sync_with_billing_platform
    T.bind(self, ::Billing::Types::Account)
    customer = billable_owner.customer
    return unless customer.present?
    Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
  end

  sig { params(commercial_restriction_feature_type: T.any(String, Symbol)).returns(MeteredServicesBillableResult) }
  def metered_services_billable?(commercial_restriction_feature_type: :default)
    T.bind(self, ::Billing::Types::Account)
    if billable_owner.feature_flag_enabled?(:billing_use_cpwu_for_copilot_billable_check, default: false)
      use_cpwu_with_legacy_billable_fallback = billable_owner.feature_flag_enabled?(:billing_use_cpwu_with_legacy_billable_fallback, default: true)
      metered_services_billable_result = science "metered_services_billable_using_cpwu" do |e|
        e.context({ billable_entity_id: billable_owner.id, billable_entity_login: billable_owner.display_login, customer_id: billable_owner.customer&.id })
        e.use do
          if use_cpwu_with_legacy_billable_fallback
            can_proceed_with_usage_with_fallback?
          else
            { cpwu: can_proceed_with_usage?, legacy: nil }
          end
        end
        e.try do
          { cpwu: nil, legacy: metered_services_billable_legacy?(commercial_restriction_feature_type:) }
        end
        e.compare do |control, candidate|
          cpwu_result = control[:cpwu]
          legacy_result = candidate[:legacy]

          billable_match = cpwu_result[:billable] == legacy_result[:billable]
          next true if Rails.env.test? && billable_match # rubocop:disable GitHub/DoNotBranchOnRailsEnv

          if legacy_result[:billable] && legacy_result[:reason] == :zuora_valid_payment_method && !cpwu_result[:billable] && cpwu_result[:reason] == :NotBillable
            # This mismatch likely indicates that billing platform doesn't have the latest information from dotcom
            # The typical case is that billing platform doesn't know of the account's existing Zuora subscription
            sync_with_billing_platform
          end

          matching_legacy_reasons = reasons_mapping[cpwu_result[:reason]]
          reasons_match = matching_legacy_reasons && matching_legacy_reasons.include?(legacy_result[:reason])
          billable_match && reasons_match
        end
      end
      return metered_services_billable_result[:cpwu] if use_cpwu_with_legacy_billable_fallback && metered_services_billable_result[:cpwu][:billable]
      return metered_services_billable_result[:cpwu] unless use_cpwu_with_legacy_billable_fallback
      metered_services_billable_result[:legacy]
    else
      metered_services_billable_legacy?(commercial_restriction_feature_type:)
    end
  end

  sig { returns(T::Hash[Symbol, T::Array[Symbol]]) }
  def reasons_mapping
    {
      BillingLocked: [:disabled, :metered_services_locked, :suspended],
      FullTradeRestrictionsApplied: [:has_full_trade_restrictions],
      AnyTradeRestrictionsApplied: [:has_any_trade_restrictions],
      NotBillable: [:suspended, :non_azure_no_zuora_account, :non_azure_no_zuora_subscription, :metered_through_azure_with_no_azure_subscription_id, :zuora_invoiced_subscription, :unknown],
      UsageAllowed: [:zuora_invoiced_subscription, :zuora_valid_payment_method, :azure_subscription_id],
      CommercialInteractionRestrictionApplied: [:unknown],
      BudgetLimitReached: [:unknown],
      OnTrial: [:unknown, :non_azure_no_zuora_account],
      ProductNotEnabled: [:unknown],
      TrustTierUsageLimitReached: [:unknown],
      error: [:non_azure_no_zuora_account]
    }
  end

  sig { params(commercial_restriction_feature_type: T.any(String, Symbol)).returns(ExperimentMeteredServicesBillableResult) }
  def can_proceed_with_usage_with_fallback?(commercial_restriction_feature_type: :default)
    {
      cpwu: can_proceed_with_usage?,
      legacy: metered_services_billable_legacy?(commercial_restriction_feature_type:)
    }
  end

  sig { returns(MeteredServicesBillableResult) }
  def can_proceed_with_usage?
    T.bind(self, ::Billing::Types::Account)
    with_database_error_fallback(fallback: { billable: false, reason: :unknown }) do
      # There is only one SKU for individual accounts, which is copilot_premium_request, so that's the default for now
      product_sku_name = "copilot_premium_request"
      if billable_owner.business? || billable_owner.organization?
        emission_information = ::Copilot::Billing::Emittable.new(T.cast(billable_owner, ::Billing::Types::OrgOrBusiness))
        product_sku_name = emission_information.product_sku_name
      end
      request_params = ::Billing::Platform::CanProceedWithUsage::RequestParams.new(
        customer_id: billable_owner.find_or_create_customer.id,
        product: "copilot",
        sku: product_sku_name
      )
      response = Billing::Platform::CanProceedWithUsage.call(request_params)
      { billable: response.can_proceed, reason: response.status }
    end
  end

  sig { params(commercial_restriction_feature_type: T.any(String, Symbol)).returns(MeteredServicesBillableResult) }
  def metered_services_billable_legacy?(commercial_restriction_feature_type: :default)
    T.bind(self, ::Billing::Types::Account)
    with_database_error_fallback(fallback: { billable: false, reason: :unknown }) do
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
          billable_owner.feature_flag_enabled?(:strict_zuora_validation_on_metered_billable_check, default: false) ||
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
