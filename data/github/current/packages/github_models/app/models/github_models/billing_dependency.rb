# typed: true
# frozen_string_literal: true

module GitHubModels
  module BillingDependency
    extend T::Helpers

    sig { returns(T::Boolean) }
    def can_enable_models_billing?
      T.bind(self, T.any(::User, Business))
      return false if self.is_a?(Business) && self.trial?
      return false unless billable_owner.customer&.billed_via_billing_platform?
      return false if billable_owner.customer&.metered_via_azure?
      return false if billable_owner.invoiced?
      return false if billable_owner.plan.legacy? # TO CHECK: Should we allow this?
      return false if billable_owner.is_a?(::User) && T.cast(billable_owner, ::User).is_enterprise_managed? # TO CHECK: Should we allow this?
      billable_owner.has_credit_card? || billable_owner.has_paypal_account?
    end
  end
end
