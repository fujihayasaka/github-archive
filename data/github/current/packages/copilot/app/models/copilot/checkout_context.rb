# typed: strict
# frozen_string_literal: true

module Copilot
  # Value object for checkout-specific pricing and upgrade details used by Copilot signup views.
  class CheckoutContext < T::Struct
    # Discount-aware pricing for the target product (original/discounted price, coupon, etc.).
    const :pricing_data, ::Billing::PricingDisplay::PricingData
    # Amount charged today: $0 during a trial, otherwise the amount due today (upgrade delta or full plan price) less any coupon discount.
    const :billing_amount, ::Billing::Money
    # Pre-coupon amount due today: the upgrade delta when upgrading, otherwise the plan's full price.
    const :today_full_price, ::Billing::Money
    # Coupon discount applied to the amount due today; $0 when there is no coupon.
    const :today_discount, ::Billing::Money
    # Amount of the next charge: discounted while a coupon is still active, otherwise full price.
    const :next_billing_amount, ::Billing::Money
    # Date the next charge lands: trial end date, existing subscription renewal, or one billing period out.
    const :next_billing_date, Date
    # Date the coupon stops applying and regular pricing resumes; nil when there is no expiring coupon.
    const :coupon_end_date, T.nilable(Date)
    # Prorated amount due today to upgrade from the current plan to the target; nil for a non-upgrade purchase.
    const :upgrade_delta, T.nilable(::Billing::Money)

    # User's current outstanding overage spend; nil when spending info is unavailable.
    const :current_overage, T.nilable(::Billing::Money)
    # Target plan's included credits as Money; nil when the target has no included credits.
    const :target_included_credits, T.nilable(::Billing::Money)

    sig do
      params(
        pricing_data: ::Billing::PricingDisplay::PricingData,
        upgrade_delta: T.nilable(::Billing::Money),
        eligible_for_trial: T::Boolean,
        subscription_next_billing_date: T.nilable(Date),
        coupon_redemption_expires_on: T.nilable(Date),
        new_entitlement: T.nilable(Integer),
        current_overage: T.nilable(::Billing::Money)
      ).returns(CheckoutContext)
    end
    def self.build(
      pricing_data:,
      upgrade_delta:,
      eligible_for_trial:,
      subscription_next_billing_date:,
      coupon_redemption_expires_on:,
      new_entitlement:,
      current_overage:
    )
      # Pre-coupon amount due today: the prorated upgrade delta when upgrading, otherwise the
      # plan's full price for an initial purchase.
      today_full_price = upgrade_delta || pricing_data.original_price

      # Coupons discount the amount charged today (the upgrade delta when upgrading). Apply the discount to the today
      # amount so a percentage coupon scales to the delta rather than the full plan price.
      today_discount = if pricing_data.has_coupon
        if pricing_data.is_percentage_discount && pricing_data.discount_percentage
          ::Billing::Money.new((today_full_price.cents * pricing_data.discount_percentage / 100.0).round)
        else
          ::Billing::Money.new([pricing_data.discount_amount.cents, today_full_price.cents].min)
        end
      else
        ::Billing::Money.new(0)
      end

      # Amount charged today: free during a trial, otherwise the today price less any coupon discount.
      billing_amount = if eligible_for_trial
        ::Billing::Money.new(0)
      else
        ::Billing::Money.new(today_full_price.cents - today_discount.cents)
      end

      # When the next charge lands: the trial end date for trials, the existing
      # subscription's renewal date when upgrading, otherwise one billing period out.
      next_billing_date = if eligible_for_trial
        Date.today + Copilot.free_trial_length.days
      else
        subscription_next_billing_date || (Date.today + 1.month)
      end

      # Date the coupon stops applying and regular pricing resumes, if it ever expires.
      coupon_end_date = coupon_redemption_expires_on if pricing_data.has_coupon && pricing_data.coupon&.will_expire?

      # Next charge as discounted while the coupon is still active, otherwise full price.
      next_billing_amount = if pricing_data.has_coupon && (coupon_end_date.nil? || coupon_end_date > next_billing_date)
        pricing_data.discounted_price
      else
        pricing_data.original_price
      end

      target_included_credits = new_entitlement ? ::Billing::Money.new(new_entitlement) : nil

      new(
        pricing_data: pricing_data,
        billing_amount: billing_amount,
        today_full_price: today_full_price,
        today_discount: today_discount,
        next_billing_amount: next_billing_amount,
        next_billing_date: next_billing_date,
        coupon_end_date: coupon_end_date,
        upgrade_delta: upgrade_delta,
        current_overage: current_overage,
        target_included_credits: target_included_credits
      )
    end

    sig { returns(T::Boolean) }
    def has_coupon?
      pricing_data.has_coupon
    end

    sig { returns(String) }
    def formatted_original_price
      pricing_data.formatted_original_price
    end

    sig { returns(String) }
    def discount_label
      pricing_data.discount_label
    end

    sig { returns(String) }
    def formatted_next_billing_date
      next_billing_date.strftime("%B %e, %Y")
    end

    sig { returns(String) }
    def formatted_billing_amount
      billing_amount.format(no_cents_if_whole: false)
    end

    sig { returns(String) }
    def formatted_today_full_price
      today_full_price.format(no_cents_if_whole: false)
    end

    sig { returns(String) }
    def formatted_today_discount
      today_discount.format(no_cents_if_whole: false)
    end

    sig { returns(String) }
    def formatted_next_billing_amount
      next_billing_amount.format(no_cents_if_whole: false)
    end

    sig { returns(T.nilable(String)) }
    def formatted_target_included_credits
      target_included_credits&.format(no_cents_if_whole: false)
    end

    private :pricing_data
  end
end
