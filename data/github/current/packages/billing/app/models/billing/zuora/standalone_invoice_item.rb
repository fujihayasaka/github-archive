# typed: strict
# frozen_string_literal: true

class Billing::Zuora::StandaloneInvoiceItem < T::Struct
  class DiscountItem < T::Struct
    const :product_rate_plan_charge_id, String
    const :amount_in_cents, Integer

    # Returns a discount item (if applicable) for the provided coupon and subscribable.
    sig { params(coupon: T.nilable(Coupon), subscribable: Billing::ProductUUID).returns(T.nilable(DiscountItem)) }
    def self.for_coupon_and_subscribable(coupon:, subscribable:)
      # Validate that the provided coupon (if any) is applicable to the subscribable
      return nil unless coupon
      product_rate_plan_charge_id = subscribable.zuora_product_rate_plan_charge_ids.values.first
      return nil unless product_rate_plan_charge_id
      eligible_product_rate_plan_charge_ids = coupon.product_target_product_uuids
        .flat_map { |uuid| uuid.zuora_product_rate_plan_charge_ids.values }
        .to_set
      return nil unless eligible_product_rate_plan_charge_ids.include?(product_rate_plan_charge_id)

      # Calculate the raw discount amount
      base_price_in_cents = subscribable.base_price.cents
      discount_in_cents = if coupon.percentage?
        (coupon.discount.to_f * base_price_in_cents).to_i
      else
        [coupon.discount_in_cents, base_price_in_cents].min
      end
      return nil if discount_in_cents.zero?

      # Get the coupon's product rate plan charge id for the subscribable's billing cycle
      coupon_product_rate_plan_charge_id = coupon.product_uuid(subscribable.billing_cycle)&.zuora_product_rate_plan_charge_ids&.values&.first
      return nil unless coupon_product_rate_plan_charge_id

      new(product_rate_plan_charge_id: coupon_product_rate_plan_charge_id, amount_in_cents: discount_in_cents)
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_zuora
      {
        "amount" => -(BigDecimal(amount_in_cents.abs) / 100).to_f,
        "productRatePlanChargeId" => product_rate_plan_charge_id,
      }
    end
  end

  const :product_rate_plan_charge_id, String
  const :amount_in_cents, Integer
  const :quantity, Float, default: 1.0
  const :service_start_date, T.nilable(Date), default: nil
  const :service_end_date, T.nilable(Date), default: nil
  const :discount_items, T::Array[DiscountItem], default: []

  sig { returns(T::Hash[String, T.untyped]) }
  def to_zuora
    hash = {
      "amount" => (BigDecimal(amount_in_cents) / 100).to_f,
      "quantity" => quantity,
      "serviceStartDate" => (service_start_date || GitHub::Billing.today).to_s,
      "productRatePlanChargeId" => product_rate_plan_charge_id,
    }
    hash["serviceEndDate"] = service_end_date.to_s if service_end_date.present?
    hash["discountItems"] = discount_items.map(&:to_zuora) if discount_items.any?
    hash
  end
end
