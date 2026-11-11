# typed: strict
# frozen_string_literal: true

module Billing
  module BilledItemsHelper
    extend T::Helpers

    requires_ancestor { ActionController::Base }

    include GitHub::Memoizer

    SECRET_PROTECTION_ID = "secret-protection-unbundled"
    CODE_SECURITY_ID = "code-security-unbundled"

    sig { params(business: Business, sku: String).returns(T.nilable(Float)) }
    def unit_price_for_unbundled_sku(business, sku)
      pricing_response = billing_client.get_pricing(sku: sku)
      if pricing_response.is_a?(::Billing::Platform::Api::Error)
        Failbot.report(StandardError.new("Failed to fetch pricing for unbundled SKU"),
          error: pricing_response,
          business_id: business.id,
          sku: sku
        )
        return nil
      end

      pricing = pricing_response[:pricing]&.slice(:price)
      if pricing.nil?
        Failbot.report(StandardError.new("Received empty price for unbundled SKU"),
          business_id: business.id,
          sku: sku,
          response: pricing_response
        )
        return nil
      end

      pricing[:price]
    end

    sig { params(business: Business).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def build_unbundled_ghas_billed_items(business)
      return [] unless business.has_active_advanced_security_trial? && !business.advanced_security_products_bundled?

      billed_items = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

      # Secret Protection
      secret_protection_unit_price = unit_price_for_unbundled_sku(business, "ghas_secret_protection_licenses")
      secret_protection_seats = business.secret_protection.seats_used
      billed_items << {
        label: "Secret Protection",
        cost: secret_protection_unit_price.nil? ? nil : Billing::Money.new(secret_protection_unit_price * 100),
        quantity: secret_protection_seats,
        unit: "committer",
        allow_removal: secret_protection_seats > 0,
        removal_text: "This will disable Secret Protection across all of your private and internal repositories. You can re-enable at any time.",
        removal_button_text: "Disable",
        show_info: nil,
        info: nil,
        id: SECRET_PROTECTION_ID,
      }

      # Code Security
      code_security_unit_price = unit_price_for_unbundled_sku(business, "ghas_code_security_licenses")
      code_security_seats = business.code_security.seats_used
      billed_items << {
        label: "Code Security",
        cost: code_security_unit_price.nil? ? nil : Billing::Money.new(code_security_unit_price * 100),
        quantity: code_security_seats,
        unit: "committer",
        allow_removal: code_security_seats > 0,
        removal_text: "This will disable Code Security across all of your private and internal repositories. You can re-enable at any time.",
        removal_button_text: "Disable",
        show_info: nil,
        info: nil,
        id: CODE_SECURITY_ID,
      }

      billed_items
    end

    sig { params(billed_items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T.nilable(Billing::Money)) }
    def total_monthly_charge(billed_items)
      total_monthly_charge = Billing::Money.zero

      billed_items.each do |billed_item|
        if billed_item[:cost].nil?
          return nil
        end
        total_monthly_charge += billed_item[:cost] * billed_item[:quantity]
      end

      total_monthly_charge
    end

    private

    sig { returns(Billing::Platform::Api::Client) }
    memoize def billing_client
      Billing::Platform::Api::Client.new
    end
  end
end
