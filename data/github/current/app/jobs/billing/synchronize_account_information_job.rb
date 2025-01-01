# typed: true
# frozen_string_literal: true

module Billing
  class SynchronizeAccountInformationJob < ApplicationJob
    queue_as :billing

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    def perform(billing_entity)
      sync_general_account_information(billing_entity) if billing_entity.external_subscription?

      if billing_entity.is_a?(User) && billing_entity.external_sponsors_subscription?
        sync_sponsors_account_information(billing_entity)
      end
    end

    def sync_general_account_information(billing_entity)
      zuora_account = billing_entity.zuora_account
      balance = zuora_account["metrics"]["balance"]
      bill_cycle_day = zuora_account["billingAndPayment"]["billCycleDay"]

      plan_subscription = billing_entity.plan_subscription
      with_write do
        plan_subscription.update(balance_in_cents: (balance * 100).to_i)
        billing_entity.customer.update(bill_cycle_day: bill_cycle_day)
      end
    end

    def sync_sponsors_account_information(billing_entity)
      customer = billing_entity.sponsors_customer
      zuora_account = customer.zuora_account
      balance = zuora_account["metrics"]["balance"]
      bill_cycle_day = zuora_account["billingAndPayment"]["billCycleDay"]

      plan_subscription = billing_entity.sponsors_plan_subscription
      with_write do
        plan_subscription.update(balance_in_cents: (balance * 100).to_i)
        customer.update(bill_cycle_day: bill_cycle_day)
      end
    end
  end
end
