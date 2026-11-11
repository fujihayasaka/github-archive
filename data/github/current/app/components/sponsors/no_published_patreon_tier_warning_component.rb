# typed: strict
# frozen_string_literal: true

class Sponsors::NoPublishedPatreonTierWarningComponent < ApplicationComponent
  class Location < T::Enum
    enums do
      AccountSettings = new
      SponsorableSettings = new
      SponsorablesShow = new
    end
  end

  # sponsorable - User or Organization that should see the warning
  # location    - which page on GitHub is this component being rendered
  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      location: Location,
    ).void
  end
  def initialize(sponsorable:, location:)
    @sponsorable = sponsorable
    @location = location
  end

  sig { returns String }
  def call
    render Primer::Beta::Flash.new(
      icon: icon,
      scheme: scheme,
      spacious: true,
      mt: 2,
      test_selector: "patreon-campaign-warning",
    ).with_content(message)
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  sig { returns(Sponsors::NoPublishedPatreonTierWarningComponent::Location) }
  attr_reader :location

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled?
    return false unless sponsorable.sponsors_patreon_user.present?
    return false unless sponsorable.sponsors_listing.present?
    return false if listing_must_be_approved?
    return false if sponsors_patreon_user.any_valid_patreon_tiers?

    sponsorable.adminable_by?(current_user)
  end

  sig { returns SponsorsPatreonUser }
  memoize def sponsors_patreon_user
    T.must_because(sponsorable.sponsors_patreon_user) { "#render? assures it's not nil" }
  end

  sig { returns SponsorsListing }
  memoize def sponsors_listing
    T.must_because(sponsorable.sponsors_listing) { "#render? checks #sponsorable? to ensure it's not nil" }
  end

  sig { returns(Symbol) }
  def icon
    return :alert if sponsors_patreon_user.enabled_as_sponsorable?

    :info
  end

  sig { returns(Symbol) }
  def scheme
    return :danger if sponsors_patreon_user.enabled_as_sponsorable?

    :warning
  end

  sig { returns String }
  def message
    if sponsors_patreon_user.any_patreon_tiers_not_meeting_maintainer_minimum?
      min_amount_money = sponsors_listing.min_custom_tier_amount_money
      pretty_min_amount = min_amount_money.format(no_cents_if_whole: true)
      "We didn't find any published tiers belonging to a published creator page on Patreon that meet or exceed " \
        "your minimum sponsorship amount setting of #{pretty_min_amount}."
    else
      "We didn't find any published tiers belonging to a published creator page on Patreon. You need a published " \
        "creator page and at least one published Patreon tier to get sponsorships on GitHub via Patreon."
    end
  end

  sig { returns T::Boolean }
  def listing_must_be_approved?
    if location == Location::AccountSettings
      !sponsors_listing.approved?
    else
      false # any listing state is fine, don't require approved
    end
  end
end
