# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ZuoraSyncStatusComponent < ApplicationComponent
  BILLING_CYCLES = T.let(Billing::ProductUUID.billing_cycles.keys, T::Array[T.any(String, Symbol)])

  def initialize(listing:)
    @listing = listing
  end

  private

  attr_reader :listing

  def render?
    listing&.approved?
  end

  def status_icon(cycle)
    zuora_synced?(cycle) ? :check : :x
  end

  def status_color(cycle)
    zuora_synced?(cycle) ? :success : :danger
  end

  def status_background(cycle)
    zuora_synced?(cycle) ? "color-bg-success" : "color-bg-danger"
  end

  def zuora_synced?(cycle)
    synced_billing_cycles.include?(cycle)
  end

  memoize def synced_billing_cycles
    product_keys = BILLING_CYCLES.map { |cycle| listing.product_key(billing_cycle: cycle) }
    ::Billing::ProductUUID.sponsors_listings.where(product_key: product_keys).pluck(:billing_cycle)
  end
end
