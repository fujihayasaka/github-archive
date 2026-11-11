# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class BillingPolicy
    class << self
      # If the organization is part of an enterprise (i.e. has a business), then we need to check the owner
      # If the organization is standalone (i.e. has no business), then we need to skp if they are invoiced
      # Billing is enabled for organizations on Team and Enterprise plans
      def owner_billing_check_required?(owner)
        return true if owner.delegate_billing_to_business?
        return false if owner.invoiced?
        owner_type_is_billable?(owner)
      end

      def billing_feature_enabled?(owner)
        return false if GitHub.enterprise?
        return false if !owner.plan_codespaces_eligible?
        owner_type_is_billable?(owner)
      end

      def valid_organization_payment_method_configured?(organization)
        billable?(organization) || billable?(organization.business)
      end

      def billable?(billable_object)
        billable_object&.has_valid_payment_method? || billable_object&.invoiced?
      end

      private

      def owner_type_is_billable?(owner)
        # currently doesn't include free orgs and orgs on legacy plans
        owner.user? || owner.is_a?(Business) || owner.plan.business? || owner.plan.business_plus?
      end
    end
  end
end
