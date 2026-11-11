# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class BillingPlatformOnboardingForm < ApplicationForm
      form do |form|
        T.bind(self, BillingPlatformOnboardingForm)

        form.text_field(
          name: "new_customer_ids",
          label: "Customer IDs to onboard to billing platform",
          required: true
        )

        form.submit(
          name: "onboard",
          scheme: :primary,
          label: "Onboard customers",
          data: {
            confirm: "Please make sure you entered customer ids and NOT user, org or business ids. This can result in the incorrect entities being onboarded to billing platform. Are you sure you want to onboard the selected customers?"
          }
        )
      end
    end
  end
end
