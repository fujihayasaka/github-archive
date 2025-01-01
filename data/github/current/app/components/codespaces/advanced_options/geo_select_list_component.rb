# typed: strict
# frozen_string_literal: true

class Codespaces::AdvancedOptions::GeoSelectListComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T::Array[String]) }
  attr_reader :geos

  sig { returns(T.nilable(String)) }
  attr_reader :selected_location

  sig { params(geos: T::Array[String], selected_location: String).void }
  def initialize(geos:, selected_location:)
    @geos = geos
    @selected_location = selected_location
  end

  sig { params(geo: String).returns(String) }
  def display_name(geo)
    Codespaces::Locations::Geo.find(geo)&.name || geo
  end
end
