# typed: true
# frozen_string_literal: true

class Stafftools::TrustTiers::TieringDetailComponent < ApplicationComponent
  attr_reader :name, :note, :value

  def initialize(name, value, note = nil)
    @name = name
    @note = note
    @value = value
  end
end
