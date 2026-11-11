# typed: strict
# frozen_string_literal: true

module Billing
  class SynchronizeAccountInformationJob < ApplicationJob
    queue_as :billing

    ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        Failbot.report(error)
      end
    end

    sig { params(billable_entity: Billing::Types::Account).void }
    def perform(billable_entity)
      sync_general_account_information(billable_entity) if billable_entity.external_subscription?

      if billable_entity.is_a?(User) && billable_entity.external_sponsors_subscription?
        sync_sponsors_account_information(billable_entity)
      end
    end

    sig { params(billable_entity: Billing::Types::Account).void }
    def sync_general_account_information(billable_entity)
      customer = billable_entity.customer
      return unless customer.present?

      zuora_account = customer.zuora_object_account
      return unless zuora_account.present?

      plan_subscription = billable_entity.plan_subscription
      with_write do
        plan_subscription&.update_balance_from_zuora(origin: "Billing::SynchronizeAccountInformationJob", zuora_account: zuora_account)
        customer.update(bill_cycle_day: zuora_account.bill_cycle_day)
      end
    end

    sig { params(billable_entity: Billing::Types::Account).void }
    def sync_sponsors_account_information(billable_entity)
      customer = billable_entity.sponsors_customer
      return unless customer.present?

      zuora_account = customer.zuora_object_account
      return unless zuora_account.present?

      plan_subscription = billable_entity.sponsors_plan_subscription
      with_write do
        plan_subscription&.update_balance_from_zuora(origin: "Billing::SynchronizeAccountInformationJob", zuora_account: zuora_account)
        customer.update(bill_cycle_day: zuora_account.bill_cycle_day)
      end
    end
  end
end
