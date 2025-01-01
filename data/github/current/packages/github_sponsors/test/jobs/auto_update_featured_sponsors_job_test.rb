# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
class AutoUpdateFeaturedSponsorsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsorable = create(:user, :sponsorable)
    @listing = @sponsorable.sponsors_listing
    @listing.update_featured_sponsorships_settings(enabled: true, automatic: true)
  end

  if GitHub.sponsors_enabled?
    test "adds no featured sponsors if featured sponsors is not enabled" do
      @listing.update_featured_sponsorships_settings(enabled: false, automatic: true)
      create_paid_sponsorship_with_value

      AutoUpdateFeaturedSponsorsJob.perform_now(@listing)

      assert_empty @listing.featured_sponsorships
    end

    test "adds no featured sponsors if featured sponsors is manual" do
      @listing.update_featured_sponsorships_settings(enabled: true, automatic: false)
      create_paid_sponsorship_with_value

      AutoUpdateFeaturedSponsorsJob.perform_now(@listing)

      assert_empty @listing.featured_sponsorships
    end

    test "only adds featured sponsors that are paid" do
      create(:sponsorship, :unpaid, sponsorable: @sponsorable)
      create_paid_sponsorship_with_value

      AutoUpdateFeaturedSponsorsJob.perform_now(@listing)

      assert_equal 1, @listing.featured_sponsorships.count
    end

    test "adds fewer than top n featured sponsors if there are fewer than n total sponsors" do
      num_sponsors = AutoUpdateFeaturedSponsorsJob::TOP_FEATURED_SPONSORSHIPS_COUNT - 1
      num_sponsors.times do
        create_paid_sponsorship_with_value
      end

      assert_query_count_per_table({
        sponsorships: 10,
        sponsors_listing_featured_items: 28,
        sponsors_listings: 3
      }) do
        AutoUpdateFeaturedSponsorsJob.perform_now(@listing)
      end

      assert_equal num_sponsors, @listing.featured_sponsorships.count
    end

    test "adds top n featured sponsors if there are more than n total sponsors" do
      num_sponsors = AutoUpdateFeaturedSponsorsJob::TOP_FEATURED_SPONSORSHIPS_COUNT + 1
      num_sponsors.times do
        create_paid_sponsorship_with_value
      end

      assert_query_count_per_table({
        sponsorships: 11,
        sponsors_listing_featured_items: 31,
        sponsors_listings: 3
      }) do
        AutoUpdateFeaturedSponsorsJob.perform_now(@listing)
      end

      assert_equal AutoUpdateFeaturedSponsorsJob::TOP_FEATURED_SPONSORSHIPS_COUNT, @listing.featured_sponsorships.count
    end

    test "adds top n sponsorships correctly ordered by total lifetime value" do
      sponsorships = create_sorted_sponsorships_in_random_order(10)

      assert_query_count_per_table({
        sponsorships: 11,
        sponsors_listing_featured_items: 31,
        sponsors_listings: 3
      }) do
        AutoUpdateFeaturedSponsorsJob.perform_now(@listing)
      end

      assert_equal sponsorships.map(&:id), @listing.featured_sponsorships.pluck(:featureable_id)
    end
  end

  private

  def create_sorted_sponsorships_in_random_order(num_sponsorships)
    # We want to create the sponsorships in a different order than the values, so as to not conflate sponsorships
    # being correctly ordered by value with the order of their creation.
    values = (1..num_sponsorships).to_a.shuffle
    unordered_sponsorships = values.each_with_object({}) do |value, hash|
      hash[value] = create_paid_sponsorship_with_value(value: value)
    end

    # Sort them back into order by value
    unordered_sponsorships.sort.reverse.map(&:last)
  end

  def create_paid_sponsorship_with_value(value: 100)
    sponsor = create(:user)
    sponsorship = create(:sponsorship, :paid, sponsorable: @sponsorable, sponsor: sponsor)
    create(:payouts_ledger_entry, :transfer, sponsors_listing: @sponsorable.sponsors_listing,
      amount_in_subunits: value, sponsor: sponsor)
    sponsorship
  end
end
