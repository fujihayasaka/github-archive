# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class BillingPlatformOnboardingAccountsForm < ApplicationForm

      def initialize
      end

      form do |form|
        T.bind(self, BillingPlatformOnboardingAccountsForm)

        form.text_field(
          name: "new_ids",
          label: "Account IDs (user or org) to onboard to billing platform",
          required: true
        )

        form.submit(
          name: "onboard",
          scheme: :primary,
          label: "Onboard accounts",
          data: {
            confirm: "Please make sure you entered account ids for either a user or an org and NOT a customer id or business ID. This can result in the incorrect entities being onboarded to billing platform. Are you sure you want to onboard the selected user or organization?"
          }
        )
      end
    end
  end
end
