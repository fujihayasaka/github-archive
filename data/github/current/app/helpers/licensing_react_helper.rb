# typed: strict
# frozen_string_literal: true

module LicensingReactHelper
  extend T::Helpers
  include BillingSettingsHelper
  include ActionView::Helpers::TextHelper

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

  sig { params(business: Business).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def invoice_license_react_payload(business)
    return nil unless business.feature_enabled?(:ghe_sales_serve_renewals)
    return nil unless business.invoiced?
    return nil unless business.sales_managed_subscription_self_serve_eligible?
    return nil if business.past_due_invoice?

    payload = {}
    payload[:actionType] = :upgrade if business.eligible_for_upgrade?
    payload[:actionType] = :renewal if business.eligible_for_renewal?

    payload.merge({
      renewalScheduledStartDate: business.renewal_scheduled_start_datetime&.iso8601,
      isGHERenewal: business.ghe_renewal?,
      statusMessage: T.let(enterprise_status_inline_message(business: business), T.nilable(StatusMessage)),
    })
  end

  class StatusMessage < T::Struct
    class Variants < T::Enum
      enums do
        Success = new
        Critical = new
      end
    end

    const :variant, Variants
    const :text, String
  end

  sig { params(business: Business).returns(T.nilable(StatusMessage)) }
  def enterprise_status_inline_message(business:)
    if business.has_any_failed_change_requests?
      return StatusMessage.new(
        variant: StatusMessage::Variants::Critical,
        text: "Your Enterprise Cloud seats upgrade failed, please contact sales.",
      )
    end

    if business.has_any_pending_update_requests?
      if business.update_seat_quantity_difference.positive?
        return StatusMessage.new(
          variant: StatusMessage::Variants::Success,
          text: "Your upgrade of #{pluralize(business.update_seat_quantity_difference, 'Enterprise Cloud seat')} is being processed.",
        )
      end

      return StatusMessage.new(
        variant: StatusMessage::Variants::Success,
        text: "Your Enterprise Cloud upgrade is being processed.",
      )
    end

    nil
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
      invoiceLicenseInfo: invoice_license_react_payload(business),
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
