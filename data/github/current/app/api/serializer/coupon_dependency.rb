# typed: strict
# frozen_string_literal: true

module Api::Serializer::CouponDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  sig do
    params(
      coupon_redemption: T.nilable(CouponRedemption),
      options: T.nilable(GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def coupon_redemption_hash(coupon_redemption, options = nil)
    return nil if !coupon_redemption
    coupon = T.must(coupon_redemption.coupon)
    {
      code: coupon.code,
      discount: coupon.human_discount,
      expires_at: time(coupon_redemption.expires_at),
    }
  end

  # Creates a Hash to be serialized to JSON.
  sig do
    params(
      coupon: T.nilable(Coupon),
      options: T.nilable(GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def coupon_hash(coupon, options = nil)
    return nil if !coupon
    {
      code: coupon.code,
      discount: coupon.human_discount,
      expires_at: time(coupon.expires_at),
    }
  end
end
