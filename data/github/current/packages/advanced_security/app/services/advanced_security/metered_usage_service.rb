# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  class MeteredUsageService
    sig { void }
    def initialize
      @client = T.let(::Billing::Platform::Api::Client.new, Billing::Platform::Api::Client)
    end

    sig { params(entity: T.any(Business, Organization), sku: GitHub::Turboghas::SKU, reason: String).void }
    def lock_sku_for_entity(entity, sku, reason)
      case sku
      when GitHub::Turboghas::SKU::Bundled
        entity.lock_advanced_security_metered_usage(reason)
      when GitHub::Turboghas::SKU::CodeSecurity
        entity.lock_code_security_metered_usage(reason)
      when GitHub::Turboghas::SKU::SecretSecurity
        entity.lock_secret_protection_metered_usage(reason)
      end
    end

    sig { params(entity: T.any(Business, Organization), sku: GitHub::Turboghas::SKU).returns(T::Boolean) }
    def sku_locked_for_entity?(entity, sku)
      case sku
      when GitHub::Turboghas::SKU::Bundled
        entity.advanced_security_metered_usage_locked_for_entity?
      when GitHub::Turboghas::SKU::CodeSecurity
        entity.code_security_metered_usage_locked_for_entity?
      when GitHub::Turboghas::SKU::SecretSecurity
        entity.secret_protection_metered_usage_locked_for_entity?
      end
    end

    sig { params(customer_id: Integer, sku: GitHub::Turboghas::SKU).returns([T::Boolean, String]) }
    def can_proceed_with_usage?(customer_id, sku)
      case sku
      when GitHub::Turboghas::SKU::Bundled
        billing_sku = "ghas_licenses"
      when GitHub::Turboghas::SKU::CodeSecurity
        billing_sku = "ghas_code_security_licenses"
      when GitHub::Turboghas::SKU::SecretSecurity
        billing_sku = "ghas_secret_protection_licenses"
      end

      entity_detail = BillingPlatform::Base::EntityDetail.new(customerId: customer_id.to_s)

      usage_key = BillingPlatform::Api::V1::UsageKey.new(
        product: "ghas",
        sku: billing_sku,
        entityDetail: entity_detail,
        # check usage for 1 additional license. Note: this is currently ignored by the backend
        quantity: 1.0,
      )
      response = @client.can_proceed_with_usage(usage_key: usage_key)

      reason = "Unknown"
      if response.is_a?(Hash) && response.has_key?(:canProceed)
        reason = response[:status] if !response[:status].empty?
        return [false, reason.to_s] if !response[:canProceed]
      else
        GitHub.logger.error("Unexpected response from canProceedWithUsage API",
          { "gh.response": response.inspect, "gh.sku": sku.to_param, "gh.customer_id": customer_id })
      end

      [true, reason.to_s]
    end
  end
end
