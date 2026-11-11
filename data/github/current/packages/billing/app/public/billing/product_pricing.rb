# typed: strict
# frozen_string_literal: true

module Billing
  # Public: Calculates pricing for a single product, handling coupon discounts appropriately.
  # This provides a simpler interface than Billing::Pricing for views/controllers that need
  # to display individual product prices.
  #
  # Examples
  #
  #   # For GitHub plan pricing
  #   pricing = Billing::ProductPricing.for_plan(account: user)
  #   pricing.base_price.format        # => "$7.00"
  #   pricing.discounted_price.format  # => "$7.00" (no discount for product-targeted coupons)
  #
  #   # For subscription item pricing (Copilot, etc.)
  #   pricing = Billing::ProductPricing.for_subscription_item(subscription_item: item, account: user)
  #   pricing.base_price.format        # => "$10.00"
  #   pricing.discounted_price.format  # => "$5.00" (with Copilot coupon)
  #   pricing.has_discount?            # => true
  #
  class ProductPricing
    sig { returns(Billing::Money) }
    attr_reader :base_price

    sig { returns(Billing::Money) }
    attr_reader :discounted_price

    sig { returns(Billing::Money) }
    attr_reader :discount_amount

    sig do
      params(
        base_price: Billing::Money,
        discounted_price: Billing::Money,
        discount_amount: Billing::Money,
        coupon: T.nilable(Coupon)
      ).void
    end
    def initialize(base_price:, discounted_price:, discount_amount:, coupon:)
      @base_price = base_price
      @discounted_price = discounted_price
      @discount_amount = discount_amount
      @coupon = coupon
    end

    sig { returns(T::Boolean) }
    def has_discount?
      discount_amount.positive?
    end

    sig { returns(T::Boolean) }
    def percentage_discount?
      @coupon&.percentage? || false
    end

    sig { returns(T.nilable(Integer)) }
    def discount_percentage
      return nil unless percentage_discount?
      ((@coupon&.discount || 0) * 100).to_i
    end

    sig { returns(T::Boolean) }
    def coupon_will_expire?
      @coupon&.will_expire? || false
    end

    sig { returns(T.nilable(String)) }
    def coupon_duration_label
      return nil unless coupon_will_expire?
      @coupon&.human_duration
    end

    # Public: Creates a ProductPricing for GitHub plan (plan + seats) pricing
    sig { params(account: T.any(User, Organization)).returns(ProductPricing) }
    def self.for_plan(account:)
      pricing = Billing::Pricing.new(account: account)

      base_price = pricing.plan_and_seat_cost
      discounted_price = pricing.discounted_plan_and_seat_cost
      discount_amount = base_price - discounted_price
      coupon = discount_amount.positive? ? account.coupon : nil

      new(
        base_price: base_price,
        discounted_price: discounted_price,
        discount_amount: discount_amount,
        coupon: coupon
      )
    end

    # Public: Creates a ProductPricing for a subscription item (Copilot, etc.)
    sig do
      params(
        subscription_item: T.any(Billing::Public::SubscriptionItem, Billing::SubscriptionItem),
        account: T.any(User, Organization)
      ).returns(ProductPricing)
    end
    def self.for_subscription_item(subscription_item:, account:)
      base_price = extract_base_price(subscription_item)
      coupon = find_coupon_for_item(subscription_item, account)

      if coupon
        pricing = build_pricing_for_item(subscription_item, account, coupon)
        discounted_price = pricing.discounted
        discount_amount = pricing.discount
      else
        discounted_price = base_price
        discount_amount = Billing::Money.zero
      end

      new(
        base_price: base_price,
        discounted_price: discounted_price,
        discount_amount: discount_amount,
        coupon: coupon
      )
    end

    class << self
      private

      sig do
        params(
          subscription_item: T.any(Billing::Public::SubscriptionItem, Billing::SubscriptionItem)
        ).returns(Billing::Money)
      end
      def extract_base_price(subscription_item)
        if subscription_item.is_a?(Billing::Public::SubscriptionItem)
          subscription_item.price
        elsif subscription_item.is_a?(Billing::SubscriptionItem)
          subscribable = subscription_item.subscribable
          if subscribable.respond_to?(:base_price)
            subscribable.base_price(duration: subscribable.billing_cycle)
          else
            Billing::Money.zero
          end
        else
          Billing::Money.zero
        end
      end

      sig do
        params(
          subscription_item: T.any(Billing::Public::SubscriptionItem, Billing::SubscriptionItem),
          account: T.any(User, Organization)
        ).returns(T.nilable(Coupon))
      end
      def find_coupon_for_item(subscription_item, account)
        product_identifier = extract_product_identifier(subscription_item)
        return nil unless product_identifier

        product_type = product_identifier[:product_type]
        product_key = product_identifier[:product_key]

        return nil unless product_type && product_key

        if account.respond_to?(:coupon_for_product)
          account.coupon_for_product(product_type, product_key)
        end
      end

      sig do
        params(
          subscription_item: T.any(Billing::Public::SubscriptionItem, Billing::SubscriptionItem)
        ).returns(T.nilable(T::Hash[Symbol, T.nilable(String)]))
      end
      def extract_product_identifier(subscription_item)
        if subscription_item.is_a?(Billing::Public::SubscriptionItem)
          identifier = subscription_item.product_identifier
          { product_type: identifier.product_type, product_key: identifier.product_key }
        elsif subscription_item.is_a?(Billing::SubscriptionItem)
          subscribable = subscription_item.subscribable
          if subscribable.is_a?(Billing::ProductUUID)
            { product_type: subscribable.product_type, product_key: subscribable.product_key }
          end
        end
      end

      sig do
        params(
          subscription_item: T.any(Billing::Public::SubscriptionItem, Billing::SubscriptionItem),
          account: T.any(User, Organization),
          coupon: Coupon
        ).returns(Billing::Pricing)
      end
      def build_pricing_for_item(subscription_item, account, coupon)
        product_uuid = find_product_uuid(subscription_item)
        return Billing::Pricing.new(plan_duration: "month") unless product_uuid

        hypothetical_item = Billing::SubscriptionItem.new(
          subscribable: product_uuid,
          quantity: 1
        )

        Billing::Pricing.new(
          plan: GitHub::Plan.free,
          plan_duration: product_uuid.billing_cycle,
          coupon: coupon,
          subscription_items: [hypothetical_item],
          include_addons: true
        )
      end

      sig do
        params(
          subscription_item: T.any(Billing::Public::SubscriptionItem, Billing::SubscriptionItem)
        ).returns(T.nilable(Billing::ProductUUID))
      end
      def find_product_uuid(subscription_item)
        if subscription_item.is_a?(Billing::Public::SubscriptionItem)
          identifier = subscription_item.product_identifier
          Billing::ProductUUID.find_by(
            product_type: identifier.product_type,
            product_key: identifier.product_key,
            billing_cycle: subscription_item.interval.to_s == "month" ? "month" : "year"
          )
        elsif subscription_item.is_a?(Billing::SubscriptionItem)
          subscribable = subscription_item.subscribable
          subscribable if subscribable.is_a?(Billing::ProductUUID)
        end
      end
    end
  end
end
