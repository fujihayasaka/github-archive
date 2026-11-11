# typed: true
# frozen_string_literal: true

class Sponsors::Profile::SponsorSectionListComponent < ApplicationComponent
  # sponsorable - a User or Organization that has a SponsorsListing
  # featured_sponsorships - an Array or ActiveRecord::Relation of SponsorsListingFeaturedItem records
  # active_sponsorships - a WillPaginate::Collection of Sponsorship records
  # inactive_sponsorships - a WillPaginate::Collection of Sponsorship records
  def initialize(sponsorable:, featured_sponsorships:, active_sponsorships:, inactive_sponsorships:)
    @sponsorable = sponsorable
    @featured_sponsorships = featured_sponsorships
    @active_sponsorships = active_sponsorships
    @inactive_sponsorships = inactive_sponsorships
    ensure_sponsorships_are_paginated
  end

  private

  attr_reader :sponsorable, :featured_sponsorships, :active_sponsorships, :inactive_sponsorships
  delegate :sponsors_listing, to: :sponsorable
  delegate :hide_past_sponsorships?, to: :sponsors_listing

  def render?
    return false unless sponsorable
    active_sponsorships_count > 0 || inactive_sponsorships_count > 0 || should_render_featured_sponsors?
  end

  def ensure_sponsorships_are_paginated
    raise "sponsorships must be paginated using the .paginate method" unless active_sponsorships.respond_to?(:total_entries) && inactive_sponsorships.respond_to?(:total_entries)
  end

  def featured_sponsorships_count
    featured_sponsorships.count
  end

  def active_sponsorships_count
    active_sponsorships.total_entries
  end

  def inactive_sponsorships_count
    inactive_sponsorships.total_entries
  end

  def should_render_featured_sponsors?
    featured_sponsorships_count > 0 && sponsors_listing.featured_sponsorships_settings.enabled?
  end
end
