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

    def overage_policies_copilot_premium_requests
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?   #absence of policy means the policy is effectively enabled

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:copilot_premium_request].present?
        copilot_premium_enabled = policies_data[:SKUs][:copilot_premium_request][:enabled]
        return copilot_premium_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def overage_policies_spark
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:Products].present? && policies_data[:Products][:spark].present?
        spark_enabled = policies_data[:Products][:spark][:enabled]
        return spark_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def overage_policies_coding_agent
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:coding_agent_premium_request].present?
        coding_agent_enabled = policies_data[:SKUs][:coding_agent_premium_request][:enabled]
        return coding_agent_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def overage_policies_code_review
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:code_review_premium_request].present?
        code_review_enabled = policies_data[:SKUs][:code_review_premium_request][:enabled]
        return code_review_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def overage_policies_copilot_ai_unit
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:copilot_ai_unit].present?
        copilot_ai_unit_enabled = policies_data[:SKUs][:copilot_ai_unit][:enabled]
        return copilot_ai_unit_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def overage_policies_coding_agent_ai_unit
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:coding_agent_ai_unit].present?
        coding_agent_ai_unit_enabled = policies_data[:SKUs][:coding_agent_ai_unit][:enabled]
        return coding_agent_ai_unit_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def overage_policies_spark_ai_unit
      policies_data = customer_response.dig(:customer, :OveragePolicies)
      return "Enabled" unless policies_data.present?

      # Ensure keys can be accessed as symbols or strings
      policies_data = policies_data.with_indifferent_access
      if policies_data[:SKUs].present? && policies_data[:SKUs][:spark_ai_unit].present?
        spark_ai_unit_enabled = policies_data[:SKUs][:spark_ai_unit][:enabled]
        return spark_ai_unit_enabled == true ? "Enabled" : "Disabled"
      end

      "Enabled"
    end

    def show_policy_toggles
      if current_user&.feature_flag_enabled?(:billing_allow_stafftools_overages_toggles, default: false)
        return true
      end
      false
    end

    def enable_policy_copilot_premium_request_path
      change_policy_path(type: "sku", name: "copilot_premium_request", enabled: true)
    end

    def disable_policy_copilot_premium_request_path
      change_policy_path(type: "sku", name: "copilot_premium_request", enabled: false)
    end

    def enable_policy_coding_agent_request_path
      change_policy_path(type: "sku", name: "coding_agent_premium_request", enabled: true)
    end

    def disable_policy_coding_agent_request_path
      change_policy_path(type: "sku", name: "coding_agent_premium_request", enabled: false)
    end

    def enable_policy_spark_request_path
      change_policy_path(type: "product", name: "spark", enabled: true)
    end

    def disable_policy_spark_request_path
      change_policy_path(type: "product", name: "spark", enabled: false)
    end

    def enable_policy_code_review_request_path
      change_policy_path(type: "sku", name: "code_review_premium_request", enabled: true)
    end

    def disable_policy_code_review_request_path
      change_policy_path(type: "sku", name: "code_review_premium_request", enabled: false)
    end

    def enable_policy_copilot_ai_unit_path
      return nil unless @billable_entity.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      change_policy_path(type: "sku", name: "copilot_ai_unit", enabled: true)
    end

    def disable_policy_copilot_ai_unit_path
      return nil unless @billable_entity.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      change_policy_path(type: "sku", name: "copilot_ai_unit", enabled: false)
    end

    def enable_policy_coding_agent_ai_unit_path
      return nil unless @billable_entity.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      change_policy_path(type: "sku", name: "coding_agent_ai_unit", enabled: true)
    end

    def disable_policy_coding_agent_ai_unit_path
      return nil unless @billable_entity.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      change_policy_path(type: "sku", name: "coding_agent_ai_unit", enabled: false)
    end

    def enable_policy_spark_ai_unit_path
      return nil unless @billable_entity.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      change_policy_path(type: "sku", name: "spark_ai_unit", enabled: true)
    end

    def disable_policy_spark_ai_unit_path
      return nil unless @billable_entity.feature_flag_enabled?(:copilot_token_based_billing, default: false)
      change_policy_path(type: "sku", name: "spark_ai_unit", enabled: false)
    end

    def change_policy_path(type:, name:, enabled:)
      if @billable_entity.is_a?(Business)
        return stafftools_enterprise_billing_policy_path(@billable_entity, type: type, name: name, enabled: enabled, return_to: request&.fullpath)
      elsif @billable_entity.is_a?(Organization)
        return update_policy_stafftools_user_path(@billable_entity, type: type, name: name, enabled: enabled, return_to: request&.fullpath)
      end
      nil
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
