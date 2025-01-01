# typed: strict
# frozen_string_literal: true

module SeatsHelper
  extend T::Sig

  include MoneyHelper

  sig do
    params(seats: Integer, seat_change: ::Billing::PlanChange::SeatChange, url: String)
      .returns({
        seats: Integer,
        url: String,
        selectors: T::Hash[String, T.untyped],
      })
  end
  def hash_for_seat_change(seats, seat_change, url)
    credit_used = seat_change.credit_used * -1
    {
      seats: seats,
      url: url,
      selectors: {
        ".unstyled-delta-seats"          => seat_change.seats_delta.abs,
        ".unstyled-delta-seats-label"    => "seat".pluralize(seat_change.seats_delta.abs),
        ".unstyled-seats-label"          => "seat".pluralize(seat_change.seats),
        ".unstyled-total-seats"          => seat_change.seats,
        ".unstyled-list-price"           => seat_change.list_price.abs.format,
        ".unstyled-discounted-price"     => seat_change.discounted_price.abs.format,
        ".unstyled-payment-amount"       => seat_change.payment_amount.format,
        ".unstyled-credit-remaining"     => seat_change.credit_remaining.format,
        ".unstyled-credit-used"          => credit_used.format(sign_before_symbol: true),
        ".unstyled-renewal-price"        => seat_change.renewal_price.abs.format,
      },
    }
  end

  sig do
    params(per_seat_pricing_model: ::Billing::PlanChange::PerSeatPricingModel, url: String)
      .returns({
        plan_duration: String,
        seats: Integer,
        free: T::Boolean,
        no_additional_seats: T::Boolean,
        starting_new_subscription: T::Boolean,
        url: String,
        new_price: String,
        selectors: T::Hash[String, T.untyped],
      })
  end
  def hash_for_pricing_model_change(per_seat_pricing_model, url)
    available_plan_duration = per_seat_pricing_model.monthly_plan? ? User::BillingDependency::YEARLY_PLAN : User::BillingDependency::MONTHLY_PLAN
    {
      plan_duration: per_seat_pricing_model.plan_duration,
      seats: per_seat_pricing_model.seats,
      free: per_seat_pricing_model.final_price.zero?,
      no_additional_seats: per_seat_pricing_model.seats <= GitHub::Plan.business.base_units,
      starting_new_subscription: per_seat_pricing_model.starting_new_subscription?,
      url: url,
      new_price: per_seat_pricing_model.final_price.format,
      selectors: {
        ".unstyled-available-plan-duration-adjective" => available_plan_duration + "ly",
        ".unstyled-users-label" => "user".pluralize(per_seat_pricing_model.seats),
        ".unstyled-plan-duration-adjective" => (per_seat_pricing_model.plan_duration + "ly").capitalize,
        ".unstyled-delta-seats"           => per_seat_pricing_model.seats,
        ".unstyled-delta-seats-label"     => "seat".pluralize(per_seat_pricing_model.seats),
        ".unstyled-additional-seats"      => per_seat_pricing_model.additional_seats,
        ".unstyled-total-seats-price"     => per_seat_pricing_model.total_seats_price.format,
        ".unstyled-additional-seats-price-obj" => price_with_localization_hash(per_seat_pricing_model.additional_seats_price),
        ".unstyled-human-unit-price"      => per_seat_pricing_model.human_unit_price,
        ".unstyled-human-base-price"      => per_seat_pricing_model.human_base_price,
        ".unstyled-list-price"            => per_seat_pricing_model.renewal_list_price.format,
        ".unstyled-refund-discount"       => (per_seat_pricing_model.price_of_remaining_service * -1).format(sign_before_symbol: true),
        ".unstyled-data-packs-count"      => per_seat_pricing_model.data_pack_change.total_packs,
        ".unstyled-data-packs-unit-price" => per_seat_pricing_model.data_pack_change.human_data_pack_unit_price,
        ".unstyled-data-packs-price"      => per_seat_pricing_model.data_pack_change.renewal_price.format,
        ".unstyled-coupon-name"           => per_seat_pricing_model.coupon.to_s,
        ".unstyled-no-coupon"             => per_seat_pricing_model.coupon ? "" : "None",
        ".unstyled-coupon-description"    => per_seat_pricing_model.coupon ? "(#{per_seat_pricing_model.coupon.human_discount} for #{per_seat_pricing_model.coupon.human_duration})" : "",
        ".unstyled-coupon-discount"       => per_seat_pricing_model.coupon_discount_for_duration.format(sign_before_symbol: true),
        ".unstyled-prorated-total-price"  => per_seat_pricing_model.price_for_rest_of_billing_cycle.format(sign_before_symbol: true),
        ".unstyled-renewal-price"         => per_seat_pricing_model.renewal_price.format(sign_before_symbol: true),
        ".unstyled-base-price-obj"        => price_with_localization_hash(per_seat_pricing_model.base_price),
        ".unstyled-final-price-obj"       => price_with_localization_hash(per_seat_pricing_model.final_price),
        ".unstyled-final-price-text"      => per_seat_pricing_model.final_price.format,
      },
    }
  end

  sig { params(target: ::User).returns(T::Array[[Integer, Integer]]) }
  def seat_downgrade_options(target)
    min = [target.plan.base_units, target.filled_seats].max
    max = [target.plan.base_units, target.seats - 1].max
    (min..max).to_a.reverse.map do |seats|
      [seats, seats - target.seats]
    end
  end

  # Human-readable labels for GA reporting
  sig { params(seats: Integer).returns(String) }
  def seats_volume_bucket(seats)
    case seats
    when 1..5 then "1-5"
    when 5...20 then "6-20"
    when 20...50 then "20-50"
    when 50...100 then "50-100"
    else "100+"
    end
  end

  sig do
    params(
      actor: ::User,
      user: ::User,
      new_seat_count: Integer,
      old_seat_count: Integer,
    ).void
  end
  def publish_billing_seat_count_change_for(actor:, user:, new_seat_count: 0, old_seat_count: 0)
    GlobalInstrumenter.instrument(
      "billing.seat_count_change",
      actor_id: actor.id,
      user_id: user.id,
      old_seat_count: old_seat_count,
      new_seat_count: new_seat_count,
    )
  end
end
