# typed: true
# frozen_string_literal: true

class Sponsors::Profile::WelcomeMessageComponent < ApplicationComponent
  def initialize(sponsorship:)
    @sponsorship = sponsorship
  end

  private

  def render?
    return false unless @sponsorship.present?
    return false unless @sponsorship.active?
    return false unless tier.has_welcome_message?

    GlobalInstrumenter.instrument("sponsors.display_tier_welcome_message", {
      actor: current_user,
      sponsor: sponsor,
      tier: tier,
      listing: tier.sponsors_listing,
      sponsorable: sponsorable,
    })

    true
  end

  def sponsorable
    @sponsorship.sponsorable
  end

  def sponsor
    @sponsorship.sponsor
  end

  def tier
    @sponsorship.tier
  end

  def tier_selected_at
    @sponsorship.subscribable_selected_at
  end

  def one_time?
    tier.one_time?
  end
end
