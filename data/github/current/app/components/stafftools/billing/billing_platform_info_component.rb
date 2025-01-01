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
      customer_response.dig(:customer, :azureAccountId).presence || "None"
    end

    def zuora_account_number
      customer_response.dig(:customer, :zuoraAccountNumber).presence || "None"
    end

    def has_zuora_subscription?
      customer_response.dig(:customer, :hasZuoraSubscription).presence || "false"
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

    def sync_path
      if @billable_entity.is_a?(Business)
        sync_customer_stafftools_enterprise_path(@billable_entity)
      else
        sync_customer_stafftools_user_path(@billable_entity)
      end
    end

    def discount_plan_name
      customer_response.dig(:customer, :discountPlanName).presence || "N/A"
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

    def overage_policies_copilot_premium_requests
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Not set" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:copilot_premium_request].present?
        copilot_premium_enabled = policies_data[:SKUs][:copilot_premium_request][:enabled]
        return copilot_premium_enabled == true ? "Enabled" : "Disabled"
      end

      "Not set"
    end

    def overage_policies_spark
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Not set" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:Products].present? && policies_data[:Products][:spark].present?
        spark_enabled = policies_data[:Products][:spark][:enabled]
        return spark_enabled == true ? "Enabled" : "Disabled"
      end

      "Not set"
    end

    def overage_policies_coding_agent
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Not set" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:Products].present? && policies_data[:Products][:coding_agent].present?
        coding_agent_enabled = policies_data[:Products][:coding_agent][:enabled]
        return coding_agent_enabled == true ? "Enabled" : "Disabled"
      end

      "Not set"
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
      if customer.nil?
        {}
      else
        billing_client.get_customer(customer_id: customer.id)
      end
    end

    memoize def billing_client
      ::Billing::Platform::Api::Client.new
    end
  end
end
