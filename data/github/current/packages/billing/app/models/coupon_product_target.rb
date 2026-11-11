# typed: strict
# frozen_string_literal: true

class CouponProductTarget < ApplicationRecord::Domain::Billing
  belongs_to :coupon, inverse_of: :product_target

  validates :product_type, :product_key, presence: true
  validate :product_uuid_exists

  has_many :product_uuids,
    class_name: "Billing::ProductUUID",
    primary_key: %i[product_type product_key],
    foreign_key: %i[product_type product_key],
    inverse_of: :coupon_product_targets

  delegate :name, to: :product_uuid, prefix: :product

  sig { returns(Billing::ProductUUID) }
  def product_uuid
    product_uuids.first!
  end

  # Returns the monthly ProductUUID for this product target
  # Falls back to any available ProductUUID if no monthly version exists
  sig { returns(Billing::ProductUUID) }
  def monthly_product_uuid
    product_uuids.billing_cycle_month.first || product_uuids.first!
  end

  # Returns the yearly ProductUUID for this product target
  # Falls back to any available ProductUUID if no yearly version exists
  sig { returns(Billing::ProductUUID) }
  def yearly_product_uuid
    product_uuids.billing_cycle_year.first || product_uuids.first!
  end

  private

  sig { void }
  def product_uuid_exists
    return if Billing::ProductUUID.exists?(product_type: product_type, product_key: product_key)

    errors.add(:base, "Product with type '#{product_type}' and key '#{product_key}' does not exist")
  end
end
