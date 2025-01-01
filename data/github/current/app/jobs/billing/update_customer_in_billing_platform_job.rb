# typed: strict
# frozen_string_literal: true

module Billing
  class UpdateCustomerInBillingPlatformJob < ApplicationJob
    extend T::Sig

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

    sig { params(customer: Customer).void }
    def perform(customer)
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
          hasPaymentMethod: customer.invoiced? || customer.payment_method&.valid_payment_token?,
          hasZuoraSubscription: customer.active_plan_subscription&.zuora_subscription_number.present?,
          isBillingLocked: is_billing_locked?(billable_owner),
          isStaffOwned: customer.billable_owner.is_a?(Business) && customer.business&.staff_owned?,
          tradeScreening: {
            hasAnyTradeRestrictions: has_any_trade_restrictions?(billable_owner),
            hasFullTradeRestrictions: has_full_trade_restrictions?(billable_owner),
            featuresWithCommercialInteractionRestrictions: commercial_restrictions_for(billable_owner),
          }
        }

        billing_client = Billing::Platform::Api::Client.new
        billing_client.create_or_patch_customer(customer: customer_payload)
      end
    end

    private

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
  end
end
