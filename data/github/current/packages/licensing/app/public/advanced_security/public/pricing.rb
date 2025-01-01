# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  module Public
    module Pricing
      include Kernel
      include Billing::ProrationMath
      class ForbiddenError < StandardError; end
      class InvalidSkuError < StandardError; end
      class BlankPricingError < StandardError; end

      SKU_PRICES = T.let({
        "ghas_secret_protection_licenses" => 19.0,
        "ghas_code_security_licenses" => 30.0,
        "ghas_licenses" => 49.0,
      }.freeze, T::Hash[String, Float])

      # This price currently does not handle proration
      sig do
        params(
          seats: Integer,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle,
        ).returns(Billing::Money)
      end
      def advanced_security_price(seats:, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        T.bind(self, T.any(User, Organization, Business))
        if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Year && !self.feature_flag_enabled_or_raise?(:ghas_self_serve_post_mvp) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          raise ForbiddenError.new("Cannot display price for an advanced security subscription on an annual billing cycle")
        end
        product_identifier = if billing_cycle == Billing::Public::SubscriptionItems::BillingCycle::Month
          AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_MONTHLY_PRODUCT
        else
          AdvancedSecurity::Public::Subscription::ADVANCED_SECURITY_YEARLY_PRODUCT
        end

        # TODO: Determine service percentage remaining from the user's subscription item
        service_percentage_remaining = 1
        if self.subscribed_to_product?(product_identifier)
          result = ::Billing::Public::SubscriptionItem.all_active(product: product_identifier, account: self)
          subscription_items = result.value { [] }
          product = subscription_items.sole
          base_price = product.price
        else
          product_uuid = Billing::ProductUUID.where(product_identifier.serialize).sole
          base_price = product_uuid.base_price(duration: product_identifier.billing_cycle&.serialize)
        end

        new_price = base_price * seats
        prorate(new_price, service_percentage_remaining)
      end

      sig { params(sku: String).returns(Billing::Money) }
      def advanced_security_unit_price(sku:)
        unless SKU_PRICES.key?(sku)
          raise InvalidSkuError, "Invalid SKU: #{sku}. Must be one of: #{SKU_PRICES.keys.join(', ')}"
        end

        billing_client = ::Billing::Platform::Api::Client.new
        pricing_response = billing_client.get_pricing(sku:)

        if pricing_response.is_a?(::Billing::Platform::Api::Error) || pricing_response[:pricing].blank?
          error = pricing_response.is_a?(::Billing::Platform::Api::Error) ? pricing_response : BlankPricingError.new("Pricing response was blank")
          Failbot.report(error, sku:)
          Billing::Money.new(T.must(SKU_PRICES[sku]) * 100) # Fallback to hardcoded price
        else
          Billing::Money.new(pricing_response[:pricing][:price] * 100)
        end
      end

      sig { params(sku: String, seats: Integer, unit_price: T.nilable(Billing::Money)).returns(Billing::Money) }
      def advanced_security_price_for_sku(sku:, seats:, unit_price: nil)
        base_price = unit_price || advanced_security_unit_price(sku:)

        base_price * seats
      end
    end
  end
end
