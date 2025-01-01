# typed: true
# frozen_string_literal: true

class Sponsors::Profile::PatreonTierComponent < ApplicationComponent
  extend T::Sig

  sig do
    params(
      sponsors_patreon_tier: SponsorsPatreonTier,
      sponsorable: GitHubSponsors::Types::Sponsorable,
      sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
      sponsorship: T.nilable(Sponsorship),
    ).void
  end
  def initialize(sponsors_patreon_tier:, sponsorable:, sponsor:, sponsorship:)
    @sponsors_patreon_tier = sponsors_patreon_tier
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship = sponsorship
  end

  private

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  attr_reader :sponsorable

  sig { returns(T.nilable(GitHubSponsors::Types::Sponsor)) }
  attr_reader :sponsor

  sig { returns T.nilable(Sponsorship) }
  attr_reader :sponsorship

  sig { returns SponsorsPatreonTier }
  attr_reader :sponsors_patreon_tier

  sig { returns T.nilable(T::Boolean) }
  def render?
    sponsorable.sponsorable_via_patreon? || sponsorship&.patreon?
  end

  sig { returns(String) }
  def tier_name
    sponsors_patreon_tier.name
  end

  sig { returns(T.nilable(String)) }
  def select_tier_button_link
    if sponsoring_via_patreon?
      sponsorable_patreon_user.patreon_membership_link
    else
      sponsors_patreon_become_sponsor_path(sponsorable.display_login, sponsor: sponsor,
        campaign_id: sponsors_patreon_tier.campaign_id, cents: sponsors_patreon_tier.amount_in_cents)
    end
  end

  sig { returns SponsorsPatreonUser }
  memoize def sponsorable_patreon_user
    T.must(sponsorable.sponsors_patreon_user)
  end

  sig { returns T.nilable(T::Boolean) }
  def sponsoring_via_patreon?
    sponsorship&.patreon? && sponsor&.sponsors_patreon_user.present? &&
      T.must(sponsorship).equally_priced_tier?(sponsors_patreon_tier)
  end

  sig { returns(String) }
  def select_tier_button_text
    if sponsoring_via_patreon?
      "Manage on Patreon"
    else
      "Become a patron"
    end
  end
end
