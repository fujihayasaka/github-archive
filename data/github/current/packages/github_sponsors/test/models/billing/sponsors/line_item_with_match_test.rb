# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingSponsorsLineItemWithMatchTest < GitHub::TestCase
  test "when sponsor is not eligible for sponsorship matching, zero match" do
    sponsors_tier = build_stubbed(:sponsors_tier, :approved_sponsors_listing)
    sponsors_line_item = build_stubbed(
      :billing_transaction_line_item,
      subscribable: sponsors_tier,
      amount_in_cents: 5000_00,
    )
    sponsors_line_item.billing_transaction.user
      .stubs(:eligible_for_sponsorship_match?).returns(false)
    assert_equal 0, Billing::Sponsors::LineItemWithMatch.new(sponsors_line_item).match_amount_in_cents
  end

  test "errors when given a non-Sponsors line item" do
    marketplace_listing_plan = create(:marketplace_listing_plan, :published)
    marketplace_line_item = create(:billing_transaction_line_item,
      subscribable: marketplace_listing_plan)
    assert_raises do
      Billing::Sponsors::LineItemWithMatch.new(marketplace_line_item)
    end
  end

  test "when sponsor is an organization, zero match" do
    User.any_instance.stubs(:eligible_for_sponsorship_match?).returns(true)
    SponsorsListing.any_instance.stubs(:matchable?).returns(true)

    sponsorship = create(:sponsorship,
      sponsor: create(:organization, plan_subscription: create(:billing_plan_subscription)),
    )
    sponsors_line_item = build_stubbed(
      :billing_transaction_line_item,
      billing_transaction: create(:billing_transaction, user: sponsorship.sponsor),
      subscribable: sponsorship.tier,
      amount_in_cents: 5000_00,
    )

    assert_equal 0, Billing::Sponsors::LineItemWithMatch.new(sponsors_line_item).match_amount_in_cents
  end

  test "total_in_cents reflects the match and initial sponsorship" do
    sponsors_tier = build_stubbed(:sponsors_tier, :approved_sponsors_listing)
    sponsors_line_item = build_stubbed(
      :billing_transaction_line_item,
      subscribable: sponsors_tier,
      amount_in_cents: 2000_00,
    )

    Billing::Sponsors::LineItemWithMatch.any_instance.stubs(:match_amount_in_cents).returns(2000_00)
    sponsors_line_item_with_match = Billing::Sponsors::LineItemWithMatch.new(sponsors_line_item)

    assert_equal 4000_00, sponsors_line_item_with_match.total_in_cents
  end

  context "#sponsors_listing_id" do
    test "returns ID of Sponsors listing set on line item" do
      listing = create(:sponsors_listing)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      line_item = create(:billing_transaction_line_item, :sponsors, subscribable: tier, listing: listing)
      line_item_with_match = Billing::Sponsors::LineItemWithMatch.new(line_item)

      assert_equal listing.id, line_item_with_match.sponsors_listing_id
    end
  end
end
