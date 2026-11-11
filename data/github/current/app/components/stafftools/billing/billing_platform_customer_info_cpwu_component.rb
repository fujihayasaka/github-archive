# typed: true
# frozen_string_literal: true

module Stafftools::Billing
  class BillingPlatformCustomerInfoCpwuComponent < ApplicationComponent

    sig { params(customer: T.nilable(Customer), billing_platform_customer: T::Hash[Symbol, T.untyped], billable_status: Symbol).void }
    def initialize(customer:, billing_platform_customer:, billable_status:)
      @customer = customer
      @billing_platform_customer = billing_platform_customer
      @billable_status = billable_status
    end

    private

    def azure_subscription_id
      azure_account_id = @billing_platform_customer.dig(:customer, :azureAccountId)
      return azure_account_id if azure_account_id.present?

      "None"
    end

    def zuora_account_number
      zuora_account_number = @billing_platform_customer.dig(:customer, :zuoraAccountNumber)
      return zuora_account_number if zuora_account_number.present?

      "None"
    end

    def has_zuora_subscription?
      @billing_platform_customer.dig(:customer, :hasZuoraSubscription).presence ? "Yes" : "No"
    end

    def has_payment_method?
      @billing_platform_customer.dig(:customer, :hasPaymentMethod).presence ? "Yes" : "No"
    end

    def is_azure_billed?
      billing_target == :Azure
    end

    def billing_target
      @billing_platform_customer.dig(:customer, :billingTarget)
    end

    def render?
      (@billing_platform_customer.present? || @customer.present?) && @billable_status == :NotBillable
    end
  end
end
