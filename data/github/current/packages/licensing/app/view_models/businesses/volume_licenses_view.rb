# typed: true
# frozen_string_literal: true

class Businesses::VolumeLicensesView
  def self.for_business(business)
    new(
      consumed: business.consumed_volume_licenses,
      total_available: business.purchased_volume_licenses,
    )
  end

  attr_reader :consumed, :total_available

  def initialize(consumed:, total_available:)
    @consumed = consumed
    @total_available = total_available
  end

  def over_limit?
    consumed > total_available
  end

  def maxed_out?
    consumed >= total_available
  end

  def overage_message
    if over_limit?
      "Overallocated. If you assign this license type you will be billed for it as part of your next true-up order period."
    else
      "You can assign above your purchased user license amount. If you assign this license type you will be billed for it in your next true-up order period."
    end
  end
end
