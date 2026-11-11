# typed: strict
# frozen_string_literal: true

class Billing::Domain::Coupons < GH::Domain::Base


  # Find a coupon by its code
  sig do
    params(code: String).returns(T.nilable(Billing::ICoupon)).
      checked(:always).on_failure(:raise)
  end
  def by_code(code)
    Coupon.includes(:product_target).find_by(code: code)
  end

  # Create a new coupon
  sig do
    params(
      code: T.nilable(String),
      coupon_discount_amount: T.any(String, Integer, Float),
      coupon_group: T.nilable(String),
      coupon_expires_at: T.nilable(T.any(ActiveSupport::TimeWithZone, DateTime, String)),
      coupon_note: T.nilable(String),
      actor: ::User,
      coupon_product_target: T.nilable(Billing::Public::Product::ProductIdentifier),
      coupon_batch: T.nilable(CouponBatch),
      redemption_limit: Integer,
      redemption_duration_in_days: Integer,
      applicable_by_staff_only: T::Boolean
    ).returns(GH::Result[Billing::ICoupon])
      .checked(:always).on_failure(:raise)
  end
  def create(code:, coupon_discount_amount:, coupon_group:, coupon_expires_at:, coupon_note:, actor:, coupon_product_target: nil, coupon_batch: nil, redemption_limit: 1, redemption_duration_in_days: 7, applicable_by_staff_only: false)
    Coupon::Creator.execute(
      code: code,
      coupon_discount_amount: coupon_discount_amount,
      coupon_group: coupon_group,
      coupon_expires_at: coupon_expires_at,
      coupon_note: coupon_note,
      actor: actor,
      coupon_product_target: coupon_product_target,
      coupon_batch: coupon_batch,
      redemption_limit: redemption_limit,
      redemption_duration_in_days: redemption_duration_in_days,
      applicable_by_staff_only: applicable_by_staff_only
    )
  end

  # Destroys a coupon
  sig do
    params(code: String).returns(GH::Result[T::Boolean])
      .checked(:always).on_failure(:raise)
  end
  def destroy(code)
    coupon = Coupon.find_by_code(code)
    unless coupon
      return GH::Result::Error::NotFound.new("coupon not found for code #{code}")
    end

    if coupon.destroy
      GH::Result::Ok.new(true)
    else
      GH::Result::Error::Unprocessable.new([coupon], coupon.errors.full_messages)
    end
  end
end
