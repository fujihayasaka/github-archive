# typed: true
# frozen_string_literal: true

module Billing
  class ProductUUID < ApplicationRecord::Domain::Users
    GITHUB_PLAN_TYPE = GitHub::Billing::ZuoraDependency::ZUORA_PRODUCT_TYPE
    LFS_PRODUCT_TYPE = Asset::Status::ZuoraDependency::ZUORA_PRODUCT_TYPE
    COPILOT_PRODUCT_TYPE = "github.copilot"
    MARKETPLACE_PRODUCT_TYPE = Marketplace::ListingPlan::ZuoraDependency::ZUORA_PRODUCT_TYPE
    SPONSORS_LISTING_PRODUCT_TYPE = SponsorsListing::ZuoraDependency::ZUORA_PRODUCT_TYPE
    SPONSORS_TIER_PRODUCT_TYPE = SponsorsTier::ZuoraDependency::ZUORA_PRODUCT_TYPE

    SPONSORS_PRODUCT_TYPES = [SPONSORS_LISTING_PRODUCT_TYPE, SPONSORS_TIER_PRODUCT_TYPE].freeze
    BILLABLE_PRODUCT_TYPES = (SPONSORS_PRODUCT_TYPES + [MARKETPLACE_PRODUCT_TYPE]).freeze
    SUBSCRIBABLE_PRODUCT_TYPES = [COPILOT_PRODUCT_TYPE, MARKETPLACE_PRODUCT_TYPE, SPONSORS_TIER_PRODUCT_TYPE].freeze

    ONE_TIME_BILLING_CYCLE = "one_time"

    enum :billing_cycle, {
      User::BillingDependency::MONTHLY_PLAN => 0,
      User::BillingDependency::YEARLY_PLAN => 1,
      ONE_TIME_BILLING_CYCLE => 2,
    }, prefix: true

    has_many :subscription_items,
             class_name: "Billing::SubscriptionItem",
             as: :subscribable,
             inverse_of: :subscribable,
             dependent: :destroy

    has_many :billing_transaction_line_items,
      class_name: "Billing::BillingTransaction::LineItem",
      as: :subscribable,
      inverse_of: :subscribable

    has_many :pending_subscription_item_changes,
      class_name: "Billing::PendingSubscriptionItemChange",
      as: :subscribable,
      dependent: :destroy

    validates :zuora_product_id, presence: true
    validates :zuora_product_rate_plan_id, presence: true, uniqueness: { case_sensitive: false }
    validates :zuora_product_rate_plan_charge_ids, presence: true
    validates :billing_cycle, presence: true

    serialize :zuora_product_rate_plan_charge_ids, type: Hash

    scope :github_products, -> {
      where("product_type LIKE 'github.%'")
        .where.not(product_type: "github.coupon")
    }

    scope :non_metered_github_plans, -> {
      where(product_type: GITHUB_PLAN_TYPE).where.not(metered: true)
    }

    # Only GitHub plans and LFS v0 are discountable
    scope :discountable, -> {
      where(product_type: GITHUB_PLAN_TYPE).or(where(product_type: LFS_PRODUCT_TYPE, product_key: "v0"))
    }
    scope :for_billing_interval, ->(billing_interval) { where(billing_cycle: billing_interval) }
    scope :discounts, -> { where(product_type: "github.coupon") }
    scope :marketplace, -> { where(product_type: MARKETPLACE_PRODUCT_TYPE) }
    scope :sponsors, ->  { where(product_type: SPONSORS_PRODUCT_TYPES) }
    scope :sponsors_tiers, -> { where(product_type: SPONSORS_TIER_PRODUCT_TYPE) }
    scope :sponsors_listings, -> { where(product_type: SPONSORS_LISTING_PRODUCT_TYPE) }
    scope :copilot, -> { where(product_type: COPILOT_PRODUCT_TYPE) }
    scope :billable, -> { where(product_type: BILLABLE_PRODUCT_TYPES) }
    scope :subscribable, -> { where(product_type: SUBSCRIBABLE_PRODUCT_TYPES, metered: false) }
    scope :with_product_key, ->(product_key) { where(product_key: product_key) }
    scope :for_zuora_product_rate_plan, ->(rate_plan_id) { where(zuora_product_rate_plan_id: rate_plan_id) }
    scope :metered, -> { where(metered: true) }

    class Charge
      attr_reader :type, :name, :price, :zuora_product_rate_plan_charge_id, :billing_duration, :unit_of_measure

      def initialize(type:, name:, price:, billing_duration:, zuora_product_rate_plan_charge_id:, unit_of_measure: nil)
        @type = type
        @name = name
        @price = price
        @billing_duration = billing_duration
        @zuora_product_rate_plan_charge_id = zuora_product_rate_plan_charge_id
        @unit_of_measure = unit_of_measure
      end

      def as_json(options = {})
        {
          type: type,
          name: name,
          billing_duration: billing_duration,
          price: price,
          zuora_product_rate_plan_charge_id: zuora_product_rate_plan_charge_id,
          unit_of_measure: unit_of_measure,
        }
      end
    end

    def codename
      "#{product_type}.#{product_key}.#{billing_cycle}"
    end

    def pending_subscription_item_change(account:)
      return nil unless account.present?
      account.pending_subscription_item_changes.where(subscribable: self).first
    end

    def base_price(duration: billing_cycle)
      duration = duration.to_s
      uuid =
        case duration
        when "month"
          monthly_uuid
        when "year"
          yearly_uuid
        end

      # TODO:....BillingError is an exception defined by the public interface.
      # It doesn't seem right to be raising it here. May need to rethink this exception
      raise Billing::Public::BillingError.new("no product record for the duration specified") unless uuid

      charge = uuid.charges.detect { |charge| charge["billing_duration"].to_s == uuid.billing_cycle.to_s }
      raise Billing::Public::BillingError.new("No charge for this billing duration") if charge.nil?

      # charge["price"] is Integer representing dollars
      Billing::Money.new(charge["price"].to_d * 100)
    end

    def eligible_for_free_trial?(subscription_items:, excluded_subscription_item: nil)
      items = subscription_items.select do |item|
        item.subscribable.is_a?(self.class) &&
        item.subscribable.product_type == product_type && item.subscribable.product_key == product_key
      end
      items = items.reject { |item| item == excluded_subscription_item } if excluded_subscription_item
      items.empty?
    end

    ## Subsribable API Stuffs
    def monthly_price_in_cents
      monthly_uuid.charges.detect { |charge| charge["billing_duration"] == "month" }["price"] * 100
    end

    def yearly_price_in_cents
      yearly_uuid.charges.detect { |charge| charge["billing_duration"] == "year" }["price"] * 100
    end

    def retired?
      false
    end

    def paid?
      base_price && base_price.positive?
    end

    def available_for_purchase?
      true
    end

    def unit_name
      unit_charges = charges.select { |charge| charge["type"] == "unit" }
      return unless unit_charges.present?

      unit_charges.first["unit_of_measure"]&.downcase&.singularize
    end

    def per_unit?
      zuora_product_rate_plan_charge_ids.keys.all? { |k| k.to_s == "unit" }
    end

    def flat_fee?
      zuora_product_rate_plan_charge_ids.keys.all? { |k| k.to_s == "flat" }
    end

    # Public: Check if the given product rate plan charge ID is of the specified type for this product.
    #
    # product_rate_plan_charge_id - a String, e.g., "8a128d0285d30e3f0185df3297015b13"
    # type - a String or Symbol representing a kind of product rate plan charge, e.g., "flat" or :fee
    #
    # Returns a Boolean.
    def rate_plan_charge_id_of_type?(product_rate_plan_charge_id, type:)
      key = zuora_product_rate_plan_charge_ids.keys.detect { |k| k.to_s == type.to_s }
      return false if key.nil?
      Array.wrap(zuora_product_rate_plan_charge_ids[key]).include?(product_rate_plan_charge_id)
    end

    def can_subscribe_with_account?(account)
      true
    end

    def has_free_trial?
      false
    end

    def product_uuid(_)
      self
    end

    def listing_product_rate_plan_id(cycle: nil)
      nil
    end

    def async_listing
      listing
    end

    def listing
      nil
    end

    def same_listing?(other_subscribable)
      # All ProductUUIDs have a nil listing, so as long as we're looking at another ProductUUID, it's for the same
      # listing as this one:
      other_subscribable.is_a?(self.class)
    end

    def matches_invoice_item?(invoice_item, match_copilot_cycle: false)
      if product_type == COPILOT_PRODUCT_TYPE && match_copilot_cycle
        billing_cycle = billing_cycle_year? ? "Annual" : "Month"
        invoice_item.charge_name_include?(name) && invoice_item.charge_name_include?(billing_cycle)
      else
        invoice_item.charge_name_include?(name)
      end
    end

    # Public: Get a description of this product UUID for use on billing line items.
    #
    # args - Hash of arguments to help build the description of a line item using this product UUID; unused for
    #        Billing::ProductUUID, added for a consistent interface with Billing::Subscribable
    #
    # Returns a String.
    def line_item_description(**args)
      "#{name} - #{billing_cycle}"
    end

    sig { params(args: T.untyped).returns(T.untyped) }
    def github_arr(*args)
      if billing_cycle_month?
        base_price * 12
      else
        base_price
      end
    end

    private

    # NOTE: yearly_uuid and monthly_uuid are a workaround for ProductUUID in SubscriptionItem
    # SubscriptionItem expects to be able to query for a monthly/yearly price directly through the subscribable. The problem is that ProductUUIDs are separate records per billing interval and so we may have a subscription item for yearly and one for monthly.
    # This workaround allows us to query for the yearly duration from the monthly and vice versa until we put in a longer term solution to this design.
    def yearly_uuid
      return @yearly_uuid if defined?(@yearly_uuid)

      @yearly_uuid =
        if billing_cycle_year?
          self
        else
          self.class.billing_cycle_year.with_product_key(product_key).find_by(product_type: product_type)
        end
    end

    def monthly_uuid
      return @monthly_uuid if defined?(@monthly_uuid)

      @monthly_uuid =
        if billing_cycle_month?
          self
        else
          self.class.billing_cycle_month.with_product_key(product_key).find_by(product_type: product_type)
        end
    end
  end
end
