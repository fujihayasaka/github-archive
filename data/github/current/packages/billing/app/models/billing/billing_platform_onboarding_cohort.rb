# typed: true
# frozen_string_literal: true

module Billing
  module BillingPlatformOnboardingCohort
    def self.list_already_onboarded_customers(customers)
      customers.select { |customer| customer.billed_via_billing_platform? }
    end

    def self.customers_info_for_cohort(customer_ids)
      customers = Customer.where(id: customer_ids)
      onboarded_customers = list_already_onboarded_customers(customers)
      {
        customer_ids: customer_ids.join(", "),
        total_customers: customers.count,
        onboarded_customers: onboarded_customers.count
      }
    end

    def self.total_cohorts
      3
    end

    def self.onboard_customers_cohort(cohort_id)
      case cohort_id
      when 1
        onboard_customers_cohort_1
      when 2
        onboard_customers_cohort_2
      when 3
        onboard_customers_cohort_3
      else
        raise ArgumentError, "Invalid cohort id: #{cohort_id}"
      end
    end

    def self.onboard_customers_cohort_1
      customer_ids = Business.where(staff_owned: true).limit(3).pluck(:customer_id)
      customers_info_for_cohort(customer_ids)
    end

    def self.onboard_customers_cohort_2
      customer_ids = Business.where(staff_owned: true).limit(3).offset(3).pluck(:customer_id)
      customers_info_for_cohort(customer_ids)
    end

    def self.onboard_customers_cohort_3
      customer_ids = Business.where(staff_owned: true).limit(3).offset(6).pluck(:customer_id)
      customers_info_for_cohort(customer_ids)
    end
  end
end
