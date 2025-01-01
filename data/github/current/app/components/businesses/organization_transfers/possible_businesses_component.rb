# typed: true
# frozen_string_literal: true

class Businesses::OrganizationTransfers::PossibleBusinessesComponent < ApplicationComponent
  include ::TextHelper

  attr_reader :from_business

  def initialize(from_business:, viewer:, query: nil)
    @from_business = from_business
    @viewer = viewer
    @query = query
  end

  private

  def business_selectable?(business)
    return false if business.trial?
    return false unless business.default_managed?

    true
  end

  def unselectable_message(business)
    if business.trial?
      "Trial enterprises cannot accept transfers"
    elsif !business.default_managed?
      "Externally managed enterprises cannot accept transfers"
    else
      "Enterprise does not accept transfers"
    end
  end

  memoize def businesses
    possible_to_businesses_for_viewer(query: @query)
  end

  def possible_to_businesses_for_viewer(query: nil)
    @viewer.businesses(membership_type: :admin)
      .where("id <> ?", from_business.id)
      .not_spammy
      .for_query(query)
      .order(name: :asc)
  end
end
