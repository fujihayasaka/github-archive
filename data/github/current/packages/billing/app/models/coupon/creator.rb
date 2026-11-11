# typed: strict
# frozen_string_literal: true

class Coupon::Creator
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
  end
  def self.execute(code:, coupon_discount_amount:, coupon_group:, coupon_expires_at:, coupon_note:, actor:, coupon_product_target: nil, coupon_batch: nil, redemption_limit: 1, redemption_duration_in_days: 7, applicable_by_staff_only: false)
    coupon_params = {
      code: code,
      discount: coupon_discount_amount,
      group: coupon_group,
      expires_at: coupon_expires_at,
      note: coupon_note,
      limit: redemption_limit,
      duration: redemption_duration_in_days,
      staff_actor_only: applicable_by_staff_only,
      coupon_batch_id: coupon_batch&.id
    }

    coupon = ::Coupon.new coupon_params
    if coupon_product_target
      coupon.assign_product_target!(product_type: coupon_product_target.product_type, product_key: T.must(coupon_product_target.product_key))
    end

    unless coupon.save
      return GH::Result::Error::Validation.new(coupon, message: "Unable to create coupon. #{coupon.errors.full_messages.to_sentence}")
    end

    if product_target = coupon.product_target
      unless product_target.save
        coupon.destroy
        return GH::Result::Error::Validation.new(product_target, message: "Unable to create coupon. #{product_target.errors.full_messages.to_sentence}")
      end

      CreateZuoraProductJob.perform_later(coupon)
    end

    GH::Result::Ok.new(coupon)
  end
end
