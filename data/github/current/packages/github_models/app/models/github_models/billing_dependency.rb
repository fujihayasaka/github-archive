# typed: true
# frozen_string_literal: true

module GitHubModels
  module BillingDependency
    extend T::Helpers

    PRODUCT = "models"
    SKU = "models_inference"

    sig { returns(T::Boolean) }
    def can_enable_models_billing?
      # Check whether the user can toggle the dropdown in the Models billing section
      T.bind(self, T.any(::User, Business))
      return false if models_billing_disabled_by_non_payment_method_reason?
      return false if payment_method_required?

      can_toggle_models_billing?
    end

    sig { returns(T::Boolean) }
    def can_show_models_billing?
      # Check whether the user can see the Models billing section and banners
      T.bind(self, T.any(::User, Business))
      return false if self.is_a?(Business) && self.trial?
      return false if billable_owner.customer && billable_owner.customer&.metered_via_azure?

      true
    end

    sig { returns(T::Boolean) }
    def has_payment_method?
      T.bind(self, T.any(::User, Business))
      billable_owner.has_credit_card? || billable_owner.has_paypal_account?
    end

    sig { returns(T::Boolean) }
    def payment_method_required?
      T.bind(self, T.any(::User, Business))
      return true if billable_owner.invoiced? && !billable_owner.zuora_account?
      !has_payment_method? && !billable_owner.invoiced?
    end

    sig { returns(T::Boolean) }
    def models_billing_disabled_by_non_payment_method_reason?
      T.bind(self, T.any(::User, Business))
      return true if !can_show_models_billing?
      return true if self.is_a?(::User) && self.business.present? && !self.business&.models_billing_enabled?
      return true if billable_owner.customer && billable_owner.customer&.metered_via_azure?
      return true if billable_owner.is_a?(::User) && T.cast(billable_owner, ::User).is_enterprise_managed? # TO CHECK: Should we allow this?

      false
    end

    private

    def can_toggle_models_billing?
      T.bind(self, T.any(::User, Business))
      # Customer records do not need to exist, they will be created once billing is enabled
      return true unless billable_owner.customer
      customer_id = T.must(billable_owner.customer).id

      entity_detail = BillingPlatform::Base::EntityDetail.new(customerId: customer_id.to_s)
      usage_key = BillingPlatform::Api::V1::UsageKey.new(
        product: PRODUCT,
        sku: SKU,
        entityDetail: entity_detail,
      )

      client = ::Billing::Platform::Api::Client.new
      response = client.can_proceed_with_usage(usage_key: usage_key)

      if response.is_a?(::Billing::Platform::Api::Error)
        return false
      elsif response[:status] == :BudgetLimitReached
        return true
      end

      response[:canProceed]
    end
  end
end
