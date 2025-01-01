# typed: true
# frozen_string_literal: true

module Billing
  class CheckBusinessOrganizationTransitionFailuresJob < BillingJob
    queue_as :billing
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }

    exempt_from_tenant_context_requirement

    # Public: Report gauge metric of organization added to business billing transition failures
    #
    # When adding an organization to a business we enqueue a BusinessOrganizationBillingJob to transition many of the
    # organization's billing attributes to match those of the business.  This job reports to a gauge in Datadog when the
    # BusinessOrganizationBillingJob has failures and manual intervention is now necessary.
    #
    # Returns nothing
    def perform
      failed_billing_transitions = ::Organization.failed_billing_transition

      failed_billing_transitions_count = failed_billing_transitions.count

      GitHub.dogstats.gauge("billing.business_organization_transition_failures.count", failed_billing_transitions_count)

      if failed_billing_transitions_count.positive?
        max_age_in_milliseconds = (Time.now.to_i - failed_billing_transitions.minimum("business_organization_memberships.created_at").to_i) * 1000

        GitHub.dogstats.gauge("billing.business_organization_transition_failures.max_age", max_age_in_milliseconds)
      end
    end
  end
end
