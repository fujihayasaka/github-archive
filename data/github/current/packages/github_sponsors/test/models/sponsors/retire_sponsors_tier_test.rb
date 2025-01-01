# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsRetireSponsorsTierTest < GitHub::TestCase
  fixtures do
    @sponsors_listing = create(:sponsors_listing)
    @sponsorable = @sponsors_listing.sponsorable
  end

  context "sponsors tier retiring" do
    test "sponsorable retires a published tier" do
      # Need at least one published tier to retire the one being tested
      create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)

      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing,
        monthly_price_in_cents: 2_00,
        yearly_price_in_cents: 24_00
      )

      Sponsors::RetireSponsorsTier.call(tier: tier, viewer: @sponsorable)

      assert_predicate tier.reload, :retired?
    end

    test "raises error when non-sponsorable attempts to retire a published tier" do
      other_user = create(:user)
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::RetireSponsorsTier::ForbiddenError do
        Sponsors::RetireSponsorsTier.call(tier: tier, viewer: other_user)
      end
      assert_equal "#{other_user.login} does not have permission to change the tier.", error.message
    end

    test "succeeds when retiring the only published tier" do
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)

      Sponsors::RetireSponsorsTier.call(tier: tier, viewer: @sponsorable)

      assert_predicate tier.reload, :retired?
    end

    test "raises error when retiring an already retired tier" do
      tier = create(:sponsors_tier, :retired, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::RetireSponsorsTier::UnprocessableError do
        Sponsors::RetireSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "Can't change the state of a retired tier.", error.message
    end

    test "raises error when retiring a draft tier" do
      tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::RetireSponsorsTier::UnprocessableError do
        Sponsors::RetireSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "This tier cannot be retired.", error.message
    end

    test "raises error when retiring a tier for a listing that is not accepted into the program" do
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)
      @sponsors_listing.actor = create(:user, :staff)
      @sponsors_listing.ban!(banned_reason: "bad things")

      error = assert_raises Sponsors::RetireSponsorsTier::ForbiddenError do
        Sponsors::RetireSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "Tiers for this Sponsors profile cannot be retired at this time.", error.message
    end
  end
end unless GitHub.enterprise?
