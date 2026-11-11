# typed: true
# frozen_string_literal: true

class Businesses::AvailableLicensesComponent < ApplicationComponent
  attr_reader :business, :available_licenses

  def initialize(business:, available_licenses:)
    @business = business
    @available_licenses = available_licenses
  end

  def render_available_licenses?
    return true unless business.metered_plan?

    business.metered_ghec_trial?
  end
end
