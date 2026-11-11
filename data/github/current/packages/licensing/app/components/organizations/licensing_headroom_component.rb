# typed: true
# frozen_string_literal: true

class Organizations::LicensingHeadroomComponent < ApplicationComponent
  def initialize(remaining_units:, unit_of_measure:, more_units_link_markup:, more_information_markup:)
    @remaining_units = remaining_units
    @unit_of_measure = unit_of_measure
    @more_units_link_markup = more_units_link_markup
    @more_information_markup = more_information_markup
  end

  private

  attr_reader :remaining_units, :unit_of_measure, :more_units_link_markup, :more_information_markup

  def remaining_seats_or_licenses
    helpers.pluralize(remaining_units, "membership")
  end
end
