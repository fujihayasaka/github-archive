# typed: true
# frozen_string_literal: true

class Sponsors::Explore::FeaturedAccountsComponent < ApplicationComponent
  MAX_ALLOWED_FEATURED = 4096
  FEATURED_ACCOUNTS_SAMPLE_SIZE = 25
  FEATURED_ORGS_SAMPLE_SIZE = 10

  private

  def render?
    GitHub.sponsors_enabled? && featured_listings.any?
  end

  memoize def featured_listings
    # We sort by payout time to ensure that once the limit of accounts has been reached, we still get new accounts
    # over time because different maintainers enter the program and get paid out. It also helps ensure we're featuring
    # accounts that are interesting enough to get paid, since we'll likely only ever show maintainers that have active
    # sponsorships (otherwise their last_payout_at would be null or old).
    listings = SponsorsListing.featured.includes(:sponsorable).order(last_payout_at: :desc)
      .limit(MAX_ALLOWED_FEATURED)

    featured_org_listings = listings.select(&:for_organization?).sample(FEATURED_ORGS_SAMPLE_SIZE)
    featured_org_listings = T.cast(featured_org_listings, T::Array[SponsorsListing])

    featured_user_sample_size = [FEATURED_ACCOUNTS_SAMPLE_SIZE - featured_org_listings.size, 0].max
    featured_user_listings = listings.select(&:for_user?).sample(featured_user_sample_size)
    featured_user_listings = T.cast(featured_user_listings, T::Array[SponsorsListing])

    shuffled_listings = (featured_user_listings + featured_org_listings).shuffle
    GitHub::PrefillAssociations.prefill_batch_method(shuffled_listings, :sponsored_by_viewer?, current_user)

    shuffled_listings
  end
end
