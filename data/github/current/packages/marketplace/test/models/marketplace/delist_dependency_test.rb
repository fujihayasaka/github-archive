# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceDelistDependencyTest < GitHub::TestCase
  test "delists apps for spammy user" do
    listing = create(:marketplace_listing, :verified,
      listable: create(:oauth_application))
    plan = create :marketplace_listing_plan, :published,
      listing: listing
    user = listing.owner

    user.spammy = true
    user.save

    assert_equal listing.reload.state, Marketplace::Listing.state_value(:archived)
  end if GitHub.spamminess_check_enabled?
end
