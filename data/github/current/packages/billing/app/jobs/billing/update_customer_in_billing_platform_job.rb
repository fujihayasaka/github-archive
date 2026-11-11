# typed: strict
# frozen_string_literal: true

module Billing
  class UpdateCustomerInBillingPlatformJob < ApplicationJob
    include ActiveJob::InitiallyEnqueuedAt

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing_platform_customer_update

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

      restraint = GitHub::Restraint.new
      restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
        customer.reload
        billable_owner = customer.billable_owner

        last_meta = last_success_meta(customer.id)
        if last_meta && last_meta[:processed_at] > initially_enqueued_at.to_f
          instrument_skipped(customer, "stale_processed_at", last_meta)
          next
        end

        customer_id_to_migrate_from = previous_customer_id || ""

        customer_payload = build_customer_payload(customer, billable_owner)
        fingerprint = payload_fingerprint(customer_payload, new_or_updated_overage_policy)
        if last_meta && last_meta[:fingerprint] == fingerprint
          instrument_skipped(customer, "same_fingerprint", last_meta)
          next
        end
        GitHub.logger.info(
          "create_or_patch_customer called",
          "code.namespace": self.class.name.to_s,
          "code.function": "perform",
          "gh.billing.customer.id": customer.id,
          "gh.billing.customer.updated_at": customer.updated_at,
          "gh.billing.customer.discount_plan_name": customer.discount_plan_name,
          "gh.billing.billing_platform.client.previous_customer_id": customer_id_to_migrate_from,
          "gh.billing.billing_platform.client.request": customer_payload,
          "gh.request_id": GitHub.context[:request_id]
        )
        response = Billing::Platform::Api::Client.new.create_or_patch_customer(customer: customer_payload, previous_customer_id: customer_id_to_migrate_from, new_or_updated_overage_policy: new_or_updated_overage_policy)
        if response.is_a?(::Billing::Platform::Api::Error)
          GitHub.dogstats.increment("billing.update_customer_in_billing_platform_job_failed", tags: [
            "error:#{response.original_error.class.name}",
            "error_code:#{response.http_status}"
          ])
          Failbot.report(
            ::Billing::Platform::Api::Error.new("Failed to update customer in billing platform"),
            "code.namespace": self.class.name.to_s,
            "code.function": "perform",
            "gh.billing.customer.id": customer.id,
            "gh.billing.previous_customer_id": customer_id_to_migrate_from,
            "gh.request_id": GitHub.context[:request_id]
          )
        else
          write_last_success_meta(customer.id, fingerprint, initially_enqueued_at.to_f)

          if new_or_updated_overage_policy
            publish_overage_policy_change_notification(customer, new_or_updated_overage_policy)
          end
        end
      end

      create_default_budgets_if_not_exists(customer)
    end

    private

    sig { params(customer: Customer, reason: String, last_meta: T::Hash[Symbol, T.untyped]).void }
    def instrument_skipped(customer, reason, last_meta)
      GitHub.dogstats.increment("billing.update_customer_in_billing_platform_job.skipped", tags: ["reason:#{reason}"])
      GitHub.logger.info(
        "Skipping stale job #{reason}",
        "code.namespace": self.class.name,
        "code.function": "perform",
        "gh.billing.customer.id": customer.id,
        "job.initially_enqueued_at": initially_enqueued_at,
        "last_processed_at": last_meta[:processed_at],
        "gh.request_id": GitHub.context[:request_id]
      )
    end

    sig { params(customer_id: Integer).returns(String) }
    def last_success_meta_key(customer_id)
      "billing_platform.customer.last_success_meta:#{customer_id}"
    end

    sig { params(customer_id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def last_success_meta(customer_id)
      raw = Billing::Kv.store.get(last_success_meta_key(customer_id)).value { nil }
      return nil unless raw
      data = JSON.parse(raw)
      fingerprint = data["fingerprint"]
      processed_at = data["processed_at"]
      return nil if fingerprint.nil? || processed_at.nil?

      { fingerprint: fingerprint.to_s, processed_at: processed_at.to_f }
    end

    sig { params(customer_id: Integer, fingerprint: String, processed_at: Float).void }
    def write_last_success_meta(customer_id, fingerprint, processed_at)
      ActiveRecord::Base.connected_to(role: :writing) do
        Billing::Kv.store.set(
          last_success_meta_key(customer_id),
          { fingerprint: fingerprint, processed_at: processed_at }.to_json,
          expires: 1.week.from_now
        )
      end
    end

    sig do
      params(
        customer_payload: T::Hash[Symbol, T.untyped],
        new_or_updated_overage_policy: T.nilable({ type: String, name: String, enabled: T::Boolean })
      ).returns(String)
    end
    def payload_fingerprint(customer_payload, new_or_updated_overage_policy)
      # Build a normalized representation of the payload for fingerprinting
      # Use JSON serialization to handle nested structures consistently
      payload_data = customer_payload.to_json
      overage_part = if new_or_updated_overage_policy
        [
          new_or_updated_overage_policy[:type],
          new_or_updated_overage_policy[:name],
          new_or_updated_overage_policy[:enabled]
        ].join(":")
      else
        "no_policy"
      end

      parts = [payload_data, overage_part]
      Digest::SHA256.hexdigest(parts.join(":"))
    end

    sig { params(customer: Customer, billable_owner: T.nilable(::Billing::Types::Account)).returns(T::Hash[Symbol, T.untyped]) }
    def build_customer_payload(customer, billable_owner)
      {
        azureAccountId: customer.azure_subscription_id,
        zuoraAccountNumber: customer.zuora_account_number,
        enableUsageEmission: true,
        customerId: customer.id.to_s,
        discountPlanName: customer.discount_plan_name,
        billingTarget: customer.billing_platform_billing_target,
        hasPaymentMethod: has_payment_method?(customer),
        hasZuoraSubscription: has_zuora_subscription?(customer),
        isBillingLocked: is_billing_locked?(billable_owner),
        isStaffOwned: billable_owner.is_a?(Business) && customer.business&.staff_owned?,
        tradeScreening: {
          hasAnyTradeRestrictions: has_any_trade_restrictions?(billable_owner),
          hasFullTradeRestrictions: has_full_trade_restrictions?(billable_owner),
          featuresWithCommercialInteractionRestrictions: commercial_restrictions_for(billable_owner),
        },
      }
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

      Hydro::PublishRetrier.publish(message, schema: "billingplatform.v1.BudgetChangedNotification", publisher: GitHub.hydro_publisher)
    end
  end
end
