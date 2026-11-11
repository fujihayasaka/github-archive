# typed: strict
# frozen_string_literal: true

class Biztools::Coupons::ZuoraSyncStatusComponent < ApplicationComponent
  BILLING_CYCLES = T.let(User::BillingDependency::PLAN_DURATIONS.dup.freeze, T::Array[String])

  sig { params(coupon: Coupon).void }
  def initialize(coupon:)
    @coupon = T.let(coupon, Coupon)
  end

  private

  sig { returns(Coupon) }
  attr_reader :coupon

  sig { returns(T::Hash[String, String]) }
  memoize def sync_errors
    BILLING_CYCLES.each_with_object({}) do |cycle, errors|
      if (detail = sync_detail(cycle))
        errors[cycle] = detail
      end
    end
  end

  sig { params(cycle: String).returns(T.nilable(String)) }
  def sync_detail(cycle)
    product_uuid = product_uuid_for(cycle)
    return "No ProductUUID record found" if product_uuid.nil?
    return product_uuid.errors.full_messages.to_sentence unless product_uuid.valid?
    return "Product not yet synced" unless product_uuid.synchronized_to_product_catalog?

    nil
  end

  sig { returns(T::Hash[String, Billing::ProductUUID]) }
  memoize def product_uuids_by_cycle
    ::Billing::ProductUUID
      .where(product_type: coupon.product_type, product_key: coupon.product_key)
      .index_by(&:billing_cycle)
  end

  sig { params(cycle: String).returns(T.nilable(Billing::ProductUUID)) }
  def product_uuid_for(cycle)
    product_uuids_by_cycle[cycle]
  end
end
