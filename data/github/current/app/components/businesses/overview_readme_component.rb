# typed: true
# frozen_string_literal: true

class Businesses::OverviewReadmeComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end

  private

  memoize def readme_editable?
    business_owner?
  end

  memoize def business_owner?
    business.owner?(current_user)
  end
end
