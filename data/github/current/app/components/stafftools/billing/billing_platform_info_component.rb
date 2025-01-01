# typed: true
# frozen_string_literal: true

module Stafftools::Billing
  class BillingPlatformInfoComponent < ApplicationComponent

    sig { params(billable_entity: ::Billing::Types::Account).void }
    def initialize(billable_entity:)
      @billable_entity = billable_entity
    end

    private

    attr_reader :billable_entity
    delegate :customer, to: :billable_entity

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
      if effective_at && effective_at > 0
        Time.at(effective_at).utc.to_datetime
      else
        "--"
      end
    end

    def migrated_to_billing_platform
      @billable_entity.customer&.billing_platform_enabled_product&.migration_date&.utc&.to_datetime
    end

    def planned_migration_date_to_billing_platform
      @billable_entity.customer&.billing_platform_enabled_product&.planned_migration_date&.utc&.strftime("%B %d, %Y %Z")
    end

    def planned_migration_email_sent_at
      @billable_entity.customer&.billing_platform_enabled_product&.email_sent_at&.utc&.strftime("%B %d, %Y at %H:%M:%S %Z")
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

    def billing_locked?
      customer_response.dig(:customer, :isBillingLocked)
    end

    memoize def customer_response
      if !customer.nil?
        billing_client.get_customer(customer_id: customer.id)
      end
    end

    memoize def billing_client
      ::Billing::Platform::Api::Client.new
    end
  end
end
