# typed: true
# frozen_string_literal: true

module Stafftools::Billing::Businesses
  class BillingPlatformInfoComponent < ApplicationComponent
    extend T::Sig

    sig { params(business: Business).void }
    def initialize(business:)
      @business = business
    end

    sig { returns(T::Boolean) }
    def render?
      business.billed_via_billing_platform?
    end

    private

    attr_reader :business
    delegate :customer, to: :business

    def azure_subscription_id
      customer_response.dig(:customer, :azureAccountId).present? ? customer_response.dig(:customer, :azureAccountId) : "None"
    end

    def zuora_account_number
      customer_response.dig(:customer, :zuoraAccountNumber).present? ? customer_response.dig(:customer, :zuoraAccountNumber) : "None"
    end

    def billing_target
      customer_response.dig(:customer, :billingTarget)
    end

    def billing_platform_effective_date
      effective_at = customer_response.dig(:customer, :effectiveAt)
      if effective_at > 0
        Time.at(effective_at).utc.to_datetime
      else
        "--"
      end
    end

    def migrated_to_billing_platform
      @business.customer&.billing_platform_enabled_product&.migration_date&.utc&.to_datetime
    end

    def enabled_products
      customer_response.dig(:customer, :enabledProducts).present? ? customer_response.dig(:customer, :enabledProducts).join(", ") : "None"
    end

    def bill_for_public_repo_usage?
      customer_response.dig(:customer, :billForPublicRepoUsage)
    end

    def customer_exists?
      customer_response[:customer].present?
    end

    memoize def customer_response
      billing_client.get_customer(customer_id: customer.id)
    end

    memoize def billing_client
      ::Billing::Platform::Api::Client.new
    end
  end
end
