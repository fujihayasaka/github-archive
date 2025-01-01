# typed: true
# frozen_string_literal: true

module Billing
  class DetachOrganizationFromBusinessCustomerJob < BillingJob
    queue_as :billing

    discard_on ActiveJob::DeserializationError

    def perform(business, organization, actor: nil)
      return if organization.plan_subscription.nil? || organization.plan_subscription.customer != business.customer

      with_write do
        if organization.customer.nil?
          organization.update! \
            customer: Billing::CreateCustomer.perform(organization, actor: actor).customer
        end

        organization.plan_subscription.update!(customer: organization.customer)
      end
    end
  end
end
