# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class BillingPlatformOnboardingCohortsForm < ApplicationForm
      extend T::Sig

      def initialize(cohorts:, products:)
        @cohorts = cohorts
        @products = products
      end

      form do |form|
        T.bind(self, BillingPlatformOnboardingCohortsForm)

        form.select_list(
          name: "bulk_id",
          label: "Select Cohort to Onboard",
          required: true,
          id: "cohort-select",
          data: { target: "cohort-widget.cohortSelect" }
        ) do |select|
          @cohorts.each do |cohort|
            select.option(
              value: cohort[:id],
              label: "#{cohort[:name]}",
              data: {
                total_customers: cohort[:members_count], # Example additional attribute
                onboarded_count: cohort[:onboarded_count], # Another example attribute
                remaining_count: cohort[:members_count] - cohort[:onboarded_count],
                new_customer_ids: cohort[:customer_ids]
              }
            )
          end
        end

        form.hidden(
          name: "new_customer_ids",
          id: "customer_ids",
          label: "Customer IDs to onboard to billing platform"
        )

        form.hidden(
          name: "remaining_count",
          id: "remaining_count",
          label: "Number of Remaining Customers to Onboard"
        )

        form.text_field(
          name: "number_to_onboard",
          label: "Number of Customers to Onboard",
          required: true
        )

        form.submit(
          name: "Onboard Cohort",
          scheme: :primary,
          label: "Onboard Cohort to Billing Platform",
          data: {
            confirm: "Please make sure you've selected the correct cohort to onboard. Are you sure you want to onboard the selected cohort?"
          }
        )
      end
    end
  end
end
