# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsMilestoneTest < GitHub::TestCase
  fixtures do
    @sponsorable = create(:user, :sponsorable)
    @listing = @sponsorable.sponsors_listing
    @recurring_tier = @listing.default_tier
    @sponsorship = create(:sponsorship, sponsorable: @sponsorable,
      tier: @recurring_tier)
    @one_time_tier = create(:sponsors_tier, :published, :one_time,
      sponsors_listing: @listing)
  end

  context ".for_listing" do
    test "does not include one-time sponsorships in count" do
      create(:sponsorship, sponsorable: @sponsorable, tier: @one_time_tier)

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 1) do
        milestone = SponsorsMilestone.for_listing(@listing)

        refute_nil milestone
        assert_equal SponsorsMilestone::TOTAL_SPONSORS_COUNT_KIND, milestone.kind
        assert_equal 1, milestone.current_value
      end
    end

    test "does not include one-time sponsorships in dollar amount" do
      create(:sponsorship, sponsorable: @sponsorable, tier: @one_time_tier)

      SponsorsMilestone.stub_const(
        :MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD,
        @recurring_tier.monthly_price_in_dollars
      ) do
        milestone = SponsorsMilestone.for_listing(@listing)

        refute_nil milestone
        assert_equal SponsorsMilestone::MONTHLY_SPONSORSHIP_AMOUNT_KIND, milestone.kind
        assert_equal @recurring_tier.monthly_price_in_dollars, milestone.current_value
      end
    end
  end
end
