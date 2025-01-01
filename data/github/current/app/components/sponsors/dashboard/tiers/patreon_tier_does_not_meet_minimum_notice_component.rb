# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Tiers::PatreonTierDoesNotMeetMinimumNoticeComponent < ApplicationComponent
  extend T::Sig

  class Location < T::Enum
    enums do
      SettingsPage = new
      TiersPage = new
    end
  end

  sig { params(sponsors_listing: SponsorsListing, location: Location).void }
  def initialize(sponsors_listing:, location:)
    @sponsors_listing = sponsors_listing
    @location = location
  end

  private

  sig { returns SponsorsListing }
  attr_reader :sponsors_listing

  sig { returns Location }
  attr_reader :location

  sig { returns T::Boolean }
  def render?
    return false unless GitHub.sponsors_enabled? && logged_in?
    return false if sponsors_listing.min_custom_tier_amount_in_cents.nil?
    return false if sponsors_listing.sponsors_patreon_user.nil?

    # If they have no valid Patreon tiers, another notice will be shown in the same place, and that notice is higher
    # priority, so we want to show it instead:
    return false if location == Location::SettingsPage && !sponsors_patreon_user.any_valid_patreon_tiers?

    sponsors_patreon_user.enabled_as_sponsorable? &&
      sponsors_patreon_user.any_patreon_tiers_not_meeting_maintainer_minimum?
  end

  sig { returns SponsorsPatreonUser }
  memoize def sponsors_patreon_user
    T.must_because(sponsors_listing.sponsors_patreon_user) { "#render? ensures it's not nil" }
  end

  sig { returns Billing::Money }
  def min_custom_amount_money
    cents = sponsors_listing.min_custom_tier_amount_in_cents
    Billing::Money.new(T.must(cents))
  end

  sig { returns T::Boolean }
  def tiers_page?
    location == Location::TiersPage
  end

  def component
    test_selector = "patreon-tier-less-than-min-amount"
    if tiers_page?
      Primer::BaseComponent.new(tag: :p, classes: "note", mt: 2, test_selector: test_selector)
    else
      Primer::Beta::Flash.new(icon: :info, mt: 3, py: 2, display: :flex, align_items: :center,
        test_selector: test_selector)
    end
  end
end
