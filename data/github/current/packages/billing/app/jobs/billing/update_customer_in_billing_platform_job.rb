# typed: strict
# frozen_string_literal: true

module Billing
  class UpdateCustomerInBillingPlatformJob < ApplicationJob

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing_platform_customer_update

    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

    RETRYABLE_ERRORS = T.let(
      [
        Net::OpenTimeout,
        Net::ReadTimeout,
      ].freeze,
      T::Array[Object],
    )

    RETRYABLE_ERRORS.each do |error_class|
      retry_on error_class do |_job, error|
        GitHub.dogstats.increment("billing.update_customer_in_billing_platform_job_failed", tags: [
          "error:#{error.class.name.underscore.parameterize}"
        ])
        Failbot.report(error)
      end
    end

    retry_on GitHub::Restraint::UnableToLock, wait: 30.seconds, attempts: 5

    resolve_tenant_context do |customer|
      customer&.business
    end

    sig { params(customer: Customer, previous_customer_id: T.nilable(String), new_or_updated_overage_policy: T.nilable({ type: String, name: String, enabled: T::Boolean })).void }
    def perform(customer, previous_customer_id = nil, new_or_updated_overage_policy = nil)
      return unless customer.present?

      lock_key = "#{self.class.name}-#{customer.id}"
      concurrent_jobs = 1
      lock_ttl = 1.minute

      billable_owner = customer.billable_owner

      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
        customer_payload = {
          azureAccountId: customer.azure_subscription_id,
          zuoraAccountNumber: customer.zuora_account_number,
          enableUsageEmission: customer.billed_via_billing_platform,
          enabledProducts: customer.products_billed_via_billing_platform,
          customerId: customer.id.to_s,
          discountPlanName: customer.discount_plan_name,
          billingTarget: customer.billing_platform_billing_target,
          hasPaymentMethod: has_payment_method?(customer),
          hasZuoraSubscription: has_zuora_subscription?(customer),
          isBillingLocked: is_billing_locked?(billable_owner),
          isStaffOwned: customer.billable_owner.is_a?(Business) && customer.business&.staff_owned?,
          tradeScreening: {
            hasAnyTradeRestrictions: has_any_trade_restrictions?(billable_owner),
            hasFullTradeRestrictions: has_full_trade_restrictions?(billable_owner),
            featuresWithCommercialInteractionRestrictions: commercial_restrictions_for(billable_owner),
          },
        }

        customer_id_to_migrate_from = previous_customer_id || ""

        billing_client = Billing::Platform::Api::Client.new
        if !billable_owner&.feature_flag_enabled?(:billing_platform_overages_policies_enabled, default: false)
          new_or_updated_overage_policy = nil
        end
        response = billing_client.create_or_patch_customer(customer: customer_payload, previous_customer_id: customer_id_to_migrate_from, new_or_updated_overage_policy: new_or_updated_overage_policy)
        if response.is_a?(::Billing::Platform::Api::Error)
          GitHub.dogstats.increment("billing.update_customer_in_billing_platform_job_failed", tags: ["error:#{T.must(response.class.name).underscore.parameterize}"])
          Failbot.report(::Billing::Platform::Api::Error.new("Failed to update customer in billing platform"), customer_id: customer.id, previous_customer_id: customer_id_to_migrate_from)
        elsif billable_owner&.feature_flag_enabled?(:billing_platform_overages_policies_enabled, default: false) && new_or_updated_overage_policy
          publish_overage_policy_change_notification(customer, new_or_updated_overage_policy)
        end
      end

      onboard_customer_to_billing_platform(customer, previous_customer_id)
      create_default_budgets_if_not_exists(customer)
    end

    private

    sig { params(customer: Customer, previous_customer_id: T.nilable(String)).void }
    def onboard_customer_to_billing_platform(customer, previous_customer_id = nil)
      return if customer.billed_via_billing_platform
      return if customer.billable_owner.nil?

      if FeatureFlag.vexi.enabled_or_raise?(:billing_check_if_org_upgraded_to_business_before_onboarding) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        return if customer.should_skip_onboard_to_billing_platform?
      end

      Billing::OnboardCustomerToProductInBillingPlatformJob.perform_later(
        customer_id: customer.id,
        products: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum.serialized_enums,
        previous_customer_id: previous_customer_id,
        unbundle_ghas: nil,
      )

      GitHub.dogstats.increment("billing_customer.onboard_customer_called_from_update_customer_job")
    end

    sig { params(customer: Customer).void }
    def create_default_budgets_if_not_exists(customer)
      return unless customer.billable_owner
      billable_owner = T.cast(customer.billable_owner, ::Billing::Types::Account)
      return unless billable_owner.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      vnext_native = T.let(customer.created_at >= Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE, T::Boolean)
      Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_later(
        customer: customer,
        set_zero_budget_limit: billable_owner.is_a?(User),
        set_copilot_default_budget_only: vnext_native && billable_owner.is_a?(Business) && !billable_owner.trial?
      )
    end

    sig { params(billable_owner: T.nilable(::Billing::Types::Account)).returns(T::Boolean) }
    def is_billing_locked?(billable_owner)
      return false unless billable_owner
      billable_owner.disabled? || billable_owner.suspended? || billable_owner.metered_services_locked?
    end

    sig { params(billable_owner: T.nilable(::Billing::Types::Account)).returns(T::Boolean) }
    def has_any_trade_restrictions?(billable_owner)
      return false unless billable_owner
      billable_owner.has_any_trade_restrictions?
    end

    sig { params(billable_owner: T.nilable(::Billing::Types::Account)).returns(T::Boolean) }
    def has_full_trade_restrictions?(billable_owner)
      return false unless billable_owner
      billable_owner.has_full_trade_restrictions?
    end

    sig { params(billable_owner: T.nilable(::Billing::Types::Account)).returns(T::Array[String]) }
    def commercial_restrictions_for(billable_owner)
      features = []
      AccountScreeningProfile::FEATURE_TYPE_ALLOW_LISTS.keys.each do |feature|
        features << feature if billable_owner&.has_commercial_interaction_restriction?(feature_type: feature)
      end
      features
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def has_zuora_subscription?(customer)
      billable_owner = customer.billable_owner
      if billable_owner.is_a?(Business)
        customer.active_plan_subscription&.zuora_subscription_number.present?
      else
        customer.plan_subscription&.zuora_subscription_number.present?
      end
    end

    sig { params(customer: Customer).returns(T::Boolean) }
    def has_payment_method?(customer)
      return false if customer.requires_azure_subscription? && customer.azure_subscription_id.blank?

      billable_owner = customer.billable_owner
      billable_owner&.invoiced? || customer.payment_method&.valid_payment_token? || false
    end

    sig { params(customer: Customer, new_or_updated_overage_policy: { type: String, name: String, enabled: T::Boolean }).void }
    def publish_overage_policy_change_notification(customer, new_or_updated_overage_policy)
      check_can_proceed_with_usage = false
      reason_type = if new_or_updated_overage_policy[:enabled]
        check_can_proceed_with_usage = true
        Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_UPDATED_HARD_LIMIT)
      else
        Hydro::Schemas::Billingplatform::V1::Entities::ReasonType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::ReasonType::BUDGET_SET_ZERO_HARD_LIMIT)
      end

      pricing_target = if new_or_updated_overage_policy[:type] == "product"
        { pricing_target_id: new_or_updated_overage_policy[:name], pricing_target_type: Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType::PRODUCT_PRICING) }
      else
        { pricing_target_id: new_or_updated_overage_policy[:name], pricing_target_type: Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType.lookup(Hydro::Schemas::Billingplatform::V1::Entities::PricingTarget::PricingTargetType::SKU_PRICING) }
      end

      message = {
        customer_id: customer.id.to_s,
        check_can_proceed_with_usage: check_can_proceed_with_usage,
        reason_type: reason_type,
        pricing_target: pricing_target,
      }

      result = Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.BudgetChangedNotification", publisher: GitHub.hydro_publisher)
    end
  end
end
