# typed: strict
# frozen_string_literal: true

class Sponsors::NewslettersComponent < ApplicationComponent
  extend T::Sig

  delegate :render_react_partial, to: :helpers

  sig { params(sponsors_listing: SponsorsListing).void }
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  sig { returns String }
  def call
    content_tag(:div, **test_selector_data_hash("sponsors-newsletter-tiers-react-partial")) do
      render_react_partial(
        name: "sponsors-newsletters",
        props: { tiers: tiers }, ssr: true
      )
    end
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def react_partial_props
    {
      tiers: tiers,
    }
  end

  private

  sig { returns T::Hash[Integer, T.untyped] }
  def tiers
    published_tiers = @sponsors_listing.published_sponsors_tiers.to_a
    retired_tiers = @sponsors_listing.retired_sponsors_tiers.with_active_sponsorships.to_a
    custom_tiers = @sponsors_listing.unique_custom_tiers.preload(:active_subscription_items).to_a
    tier_subscription_counts = @sponsors_listing.sponsorable&.tier_subscription_counts(
      custom_tier_ids: custom_tiers&.map(&:id)
    )

    tiers = published_tiers + retired_tiers + custom_tiers
    tiers.each_with_object({}) do |tier, hash|
      hash[tier.id.to_s] = {
        id: tier.id.to_s,
        name: tier.name,
        monthlyPriceInCents: tier.monthly_price_in_cents,
        frequency: tier.frequency,
        state: tier.current_state_name,
        subscriptionCount: tier_subscription_counts&.fetch(tier.id, 0),
      }
    end
  end
end
