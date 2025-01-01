# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsCalculateMatchTest < GitHub::TestCase
  fixtures do
    @sponsors_listing = create(:sponsors_listing)
    @sponsors_listing.update!(
      joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days,
      accepted_at: 1.year.ago,
    )
  end

  test "when sponsorship amount equals limit and total match is less than limit, match" do
    assert_equal 5000_00, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 5000_00)
  end

  test "when sponsorship amount and total match are equal to limit, zero match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(5000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 5000_00)
  end

  test "does not match when sponsorship listing was published over a year ago" do
    listing = create(:sponsors_listing, published_at: 2.years.ago)
    listing.update!(
      joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days,
      accepted_at: 1.year.ago,
    )
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(1000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(listing, sponsorship_amount: 1000_00)
  end

  test "matches when sponsorship listing was published less than a year ago" do
    listing = create(:sponsors_listing, :matchable, published_at: 2.days.ago, accepted_at: 15.days.ago)
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(1000_00)
    assert_equal 1000_00, Sponsors::CalculateMatch.for(listing, sponsorship_amount: 1000_00)
  end

  test "matches when sponsorship listing was published exactly a year ago" do
    travel_to(GitHub::Billing.timezone.local(2019, 9, 5)) do
      listing = create(:sponsors_listing, published_at: 1.year.ago)
      listing.update!(
        joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days,
        accepted_at: 1.year.ago,
      )
      Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(1000_00)
      assert_equal 1000_00, Sponsors::CalculateMatch.for(listing, sponsorship_amount: 1000_00)
    end
  end

  test "when sponsorship amount is equal and total match is greater than limit, zero match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(6000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 1000_000)
  end

  test "when sponsorship amount is less and total match is equal to limit, zero match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(5000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 2000_00)
  end

  test "when sponsorship amount is less and total match is greater than limit, zero match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(6000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 2000_00)
  end

  test "when sponsorship amount and total match are less than limit, match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(4000_00)
    assert_equal 1000_00, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 2000_00)
  end

  test "when sponsorship amount is greater and total match is equal to limit, zero match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(5000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 6000_00)
  end

  test "when sponsorship amount is greater and total match is less than limit, match difference to limit" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(4000_00)
    assert_equal 1000_00, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 6000_00)
  end

  test "when sponsorship amount total match are greater than limit, zero match" do
    Sponsors::CalculateMatch.any_instance.stubs(:total_ledger_amount_in_cents).returns(10_000_00)
    assert_equal 0, Sponsors::CalculateMatch.for(@sponsors_listing, sponsorship_amount: 6000_00)
  end
end
