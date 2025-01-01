# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseLicensesView
  def self.for_business(business)
    new(
      consumed: business.consumed_enterprise_licenses,
      total_available: business.seats,
    )
  end

  attr_reader :consumed, :total_available

  def initialize(consumed:, total_available:)
    @consumed = consumed
    @total_available = total_available
  end

  def maxed_out?
    consumed >= total_available
  end

  def overage_message
    "You have assigned all purchased user licenses."
  end
end
