# typed: strict
# frozen_string_literal: true

class Sponsors::Profile::PatreonTiersComponent < ApplicationComponent
  sig do
    params(
      sponsors_listing: SponsorsListing,
      sponsorable: GitHubSponsors::Types::Sponsorable,
      sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
      frequency: Symbol,
      sponsorship: T.nilable(Sponsorship),
    ).void
  end
  def initialize(sponsors_listing:, sponsorable:, sponsor:, frequency:, sponsorship:)
    @sponsors_listing = sponsors_listing
    @sponsorable = sponsorable
    @sponsor = sponsor
    @frequency = frequency
    @sponsorship = sponsorship
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  sig { returns(T.nilable(GitHubSponsors::Types::Sponsor)) }
  attr_reader :sponsor

  sig { returns(Symbol) }
  attr_reader :frequency

  sig { returns(T.nilable(Sponsorship)) }
  attr_reader :sponsorship

  sig { returns T.nilable(T::Boolean) }
  def render?
    return false unless frequency == :patreon
    sponsorable.sponsorable_via_patreon? || sponsorship&.patreon?
  end

  sig { returns T::Array[SponsorsPatreonTier] }
  def sponsors_patreon_tiers
    result = sponsorable_patreon_user.sponsors_patreon_tiers.to_a

    # Only display those Patreon tiers that meet or exceed the minimum amount the maintainer has said they require
    # for new GitHub sponsorships:
    if sponsors_listing.min_custom_tier_amount_in_cents
      result.select! do |patreon_tier|
        meets_min_amount = patreon_tier.amount_in_cents >= T.must(sponsors_listing.min_custom_tier_amount_in_cents)
        used_in_sponsorship = sponsorship&.patreon? && T.must(sponsorship).equally_priced_tier?(patreon_tier)
        meets_min_amount || used_in_sponsorship
      end
    end

    result.sort_by { |patreon_tier| patreon_tier.amount_in_cents }
  end

  sig { returns(T.nilable(SponsorsPatreonUser)) }
  def sponsor_patreon_user
    sponsor&.sponsors_patreon_user
  end

  sig { returns SponsorsPatreonUser }
  def sponsorable_patreon_user
    T.must(sponsorable.sponsors_patreon_user)
  end

  sig { returns(String) }
  def action_text
    sponsor_patreon_user.present? ? "Disconnect" : "Connect"
  end

  sig { returns T.nilable(T::Boolean) }
  def sponsoring_via_patreon?
    sponsorship&.patreon? && sponsor_patreon_user.present?
  end

  sig { returns(String) }
  def settings_path
    sponsor&.organization? ? settings_org_profile_path(sponsor) : settings_account_preferences_path
  end
end
