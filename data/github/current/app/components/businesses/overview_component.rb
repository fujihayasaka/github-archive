# typed: true
# frozen_string_literal: true

class Businesses::OverviewComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end
end
