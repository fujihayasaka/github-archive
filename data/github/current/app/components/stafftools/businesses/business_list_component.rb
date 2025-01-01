# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::BusinessListComponent < ApplicationComponent
  attr_reader :businesses, :tab

  def initialize(businesses:, tab: "active")
    @businesses = businesses
    @tab = tab
  end

  private

  def active?
    tab == "active"
  end

  def deleted?
    tab == "deleted"
  end
end
