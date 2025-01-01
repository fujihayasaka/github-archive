# typed: true
# frozen_string_literal: true

module Billing
  class DetachOrganizationFromBusinessCustomerJob < BillingJob
    discard_on ActiveJob::DeserializationError

    def perform(business, organization, actor: nil)
      with_write do
        org_customer = find_or_create_org_customer(org: organization, actor: actor)

        if organization.plan_subscription&.customer == business.customer
          organization.plan_subscription.update!(customer: org_customer)
        end

        org_customer.onboard_to_all_billing_platform_products unless org_customer.billed_via_billing_platform?
      end
    end

    private

    def find_or_create_org_customer(org:, actor:)
      if org.customer.nil?
        org.update!(customer: Billing::CreateCustomer.perform(org, details: {}, actor: actor).customer)
      end

      org.customer
    end
  end
end
