# typed: true
# frozen_string_literal: true

module Billing
  class PlanChange::DataPackChange
    include ProrationMath

    attr_reader :user, :coupon, :asset_status, :total_packs, :plan_duration

    def initialize(user, total_packs:, plan_duration: nil)
      @user = user
      @coupon = user.coupon
      @asset_status = user.asset_status || user.build_asset_status
      @total_packs = total_packs
      @plan_duration = plan_duration || user.plan_duration
    end

    delegate :sanitized_service_percent_remaining, :service_days_remaining,
      to: :subscription

    def yearly?
      plan_duration == User::BillingDependency::YEARLY_PLAN
    end

    def plan_duration_in_months
      yearly? ? 12 : 1
    end

    def delta_packs
      total_packs - asset_status.asset_packs
    end

    def data_pack_unit_price_for_duration
      data_pack_unit_price * plan_duration_in_months
    end

    def human_data_pack_unit_price
      "#{data_pack_unit_price_for_duration.format}/#{plan_duration}"
    end

    def data_pack_unit_price
      Asset::Status.data_pack_unit_price
    end

    def data_pack_storage_size
      Asset::Status::DATA_PACK_STORAGE
    end

    def data_pack_bandwidth_size
      Asset::Status::DATA_PACK_BANDWIDTH
    end

    # Public: Money total price, prorated but without discount applied.
    def undiscounted_price
      prorate(monthly_price * plan_duration_in_months, sanitized_service_percent_remaining)
    end

    # Public: Money total price due today (prorated for remaining service period,
    # with discount and balance applied.)
    def total_price
      price = prorate(discounted_price * plan_duration_in_months, sanitized_service_percent_remaining)
      [price + subscription.balance, Billing::Money.new(0)].max
    end

    # Public: Money renewal price due when subscription is next billed.
    def renewal_price
      total_packs * data_pack_unit_price * plan_duration_in_months
    end

    # Public: Float bandwidth quota
    def bandwidth_quota
      monthly_quota = [Asset::Status::FREE_STORAGE_QUOTA, total_packs * data_pack_bandwidth_size].max
      monthly_quota * plan_duration_in_months
    end

    # Public: Float storage quota
    def storage_quota
      [Asset::Status::FREE_BANDWIDTH_QUOTA, total_packs * data_pack_storage_size].max
    end

    # Public: Integer minimum number of data packs necessary to cover current
    # usage. Right now this only looks at storage.
    def min_packs_to_cover_usage
      return 0 if asset_status.storage_usage < Asset::Status::FREE_STORAGE_QUOTA
      (asset_status.storage_usage / data_pack_bandwidth_size).ceil.to_i
    end

    # Public: Array of integer data pack counts that are viable to downgrade to.
    def downgrade_options
      (min_packs_to_cover_usage..asset_status.asset_packs).to_a.reverse
    end

    def discount_applied?
      discounted_price < delta_packs * data_pack_unit_price
    end

    private

    def discounted_price
      return monthly_price unless coupon

      if coupon.percentage?
        monthly_price * (1.0 - coupon.discount).round(2)
      else
        [monthly_price - user.remaining_discount, Billing::Money.new(0)].max
      end
    end

    def monthly_price
      delta_packs * data_pack_unit_price
    end

    def subscription
      @subscription ||= Billing::Subscription.for_account(user)
    end

    # Internal: Prorate the price, but if this is an upgrade from free
    #           we special case it and just return the full price.  This is
    #           effectively because the Subscription model doesn't model non-prorated
    #           purchases properly as service_percent_remaining is always < 100%
    #
    # Returns a BigDecimal price
    def prorate(price, percent_remaining)
      prorated_purchase? ? super(price, percent_remaining) : price
    end

    def prorated_purchase?
      subscription.data_packs > 0 || !subscription.plan.free?
    end
  end
end
