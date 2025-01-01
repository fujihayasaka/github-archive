# typed: strict
# frozen_string_literal: true

class Sponsors::PatreonEnablementComponent < ApplicationComponent
  extend T::Sig

  class Location < T::Enum
    enums do
      SponsorableDashboard = new
      AccountSettings = new
    end
  end

  # sponsorable - User or Organization toggling Patreon enablement
  # location    - which GitHub page is this component being rendered on
  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      location: Sponsors::PatreonEnablementComponent::Location,
    ).void
  end
  def initialize(sponsorable:, location:)
    @sponsorable = sponsorable
    @location = location
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  sig { returns(Sponsors::PatreonEnablementComponent::Location) }
  attr_reader :location

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled?
    return false unless sponsorable.sponsors_patreon_user.present?
    return false unless sponsorable.sponsors_listing.present?
    return false if listing_must_be_approved?

    sponsorable.adminable_by?(current_user)
  end

  sig { returns SponsorsPatreonUser }
  def sponsors_patreon_user
    T.must_because(sponsorable.sponsors_patreon_user) { "#render? verifies it's not nil" }
  end

  sig { returns SponsorsListing }
  memoize def sponsors_listing
    T.must_because(sponsorable.sponsors_listing) { "#render? verifies it's not nil" }
  end

  sig { returns T::Boolean }
  def listing_must_be_approved?
    return false if location == Location::SponsorableDashboard

    !sponsors_listing.approved?
  end
end
