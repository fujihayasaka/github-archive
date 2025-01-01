# typed: strict
# frozen_string_literal: true

module LicensingReactHelper
  extend T::Helpers
  extend T::Sig
  include BillingSettingsHelper

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def payment_method_react_payload(business)
    return unless business.payment_method

    payment_method = business.payment_method
    {
      credit_card: payment_method.credit_card?,
      paypal: payment_method.paypal?,
      last_four: payment_method.last_four,
      card_type: payment_method.card_type,
    }
  end

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def trial_react_payload(business)
    return nil unless business.trial?

    {
      expirationDate: T.must(business.trial_expires_at).in_time_zone(GitHub::Billing.timezone).as_json,
      isActive: !business.trial_expired?,
      trialLicensesAllowed: business.purchased_enterprise_licenses,
    }
  end

  sig { params(business: Business, preopen_seat_management: T.nilable(T::Boolean)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def ghe_overview_react_payload(business:, preopen_seat_management: false)
    manage_seats = Business::ManageSeats.new(business: business, new_seats: nil)
    is_self_serve = business.eligible_for_self_serve_payment?
    is_self_serve_blocked = !is_self_serve || business.downgraded_to_free_plan? || business.dunning?
    pending_cycle_change = is_self_serve_blocked ? nil : pending_cycle_seat_change_payload(business)
    roles = admin_roles(business)

    is_metered_licensed = business.metered_plan?
    enterprise_licenses_consumed = business.consumed_enterprise_licenses
    current_payment = (is_metered_licensed && enterprise_licenses_consumed == 0) ? Billing::Money.new(0).format : manage_seats.current_payment

    {
      billingTermEndDate: business.billing_term_ends_on&.in_time_zone(GitHub::Billing.timezone).as_json,
      canViewMembers: roles.include?("owner"),
      currentPayment: current_payment,
      enterpriseLicensesConsumed: enterprise_licenses_consumed,
      enterpriseLicensesPurchased: business.purchased_enterprise_licenses,
      isManagingSeats: preopen_seat_management && !business.metered_plan? && is_self_serve && !is_self_serve_blocked,
      isMonthly: business.plan_duration == User::BillingDependency::MONTHLY_PLAN,
      isSelfServe: is_self_serve,
      isSelfServeBlocked: is_self_serve_blocked,
      isVolumeLicensed: !is_metered_licensed,
      isVssEnabled: business.volume_licensing_enabled?,
      paymentMethod: payment_method_react_payload(business),
      pendingCycleChange: pending_cycle_change,
      trialInfo: trial_react_payload(business),
      unitCost: manage_seats.seat_cost_label_short,
      vssLicensesConsumed: business.consumed_volume_licenses,
      vssLicensesPurchasedWithOverage: business.purchased_volume_licenses_with_overages,
    }
  end
end
