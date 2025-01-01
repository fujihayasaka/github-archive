# typed: strict
# frozen_string_literal: true

class Sponsors::Profile::PatreonActionsComponent < ApplicationComponent
  sig { params(sponsors_patreon_tier: SponsorsPatreonTier, sponsorship: T.nilable(Sponsorship)).void }
  def initialize(sponsors_patreon_tier:, sponsorship:)
    @sponsors_patreon_tier = sponsors_patreon_tier
    @sponsorship = sponsorship
  end

  private

  delegate :sponsor, :sponsorable, :opposite_privacy_level, to: :sponsorship

  delegate :opposite_email_text_for, :opposite_email_value_for, to: :helpers

  sig { returns(T.nilable(Sponsorship)) }
  attr_reader :sponsorship

  sig { returns SponsorsPatreonTier }
  attr_reader :sponsors_patreon_tier

  sig { returns(T::Boolean) }
  def render?
    return false unless sponsorship&.patreon? && sponsorship&.active?
    T.must(sponsorship).equally_priced_tier?(sponsors_patreon_tier)
  end

  sig { returns(String) }
  def update_sponsorship_url
    sponsorable_sponsorships_path(sponsorable,
      sponsor: sponsor,
    )
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def toggle_privacy_menu_item
    {
      label: "Make #{opposite_privacy_level}",
      href: update_sponsorship_url,
      form_arguments: {
        method: :put,
        name: :privacy_level,
        value: opposite_privacy_level,
      },
      data: { turbo: false },
      test_selector: "privacy-level"
    }
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def toggle_email_menu_item
    {
      label: "#{opposite_email_text_for(sponsorship)} email updates",
      href: update_sponsorship_url,
      form_arguments: {
        method: :put,
        name: :email_opt_in,
        value: opposite_email_value_for(sponsorship)
      },
      data: { turbo: false },
      test_selector: "email-updates"
    }
  end
end
