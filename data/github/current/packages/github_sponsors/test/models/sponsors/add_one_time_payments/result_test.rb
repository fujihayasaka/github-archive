# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::AddOneTimePayments::ResultTest < GitHub::TestCase
  context "#errors" do
    test "returns given list of errors" do
      result = Sponsors::AddOneTimePayments::Result.new(errors: ["error 1", "error 2"])
      assert_equal ["error 1", "error 2"], result.errors
    end
  end

  context "#sponsorables" do
    test "returns list of sponsorables from given sponsorships and subscription items" do
      sponsorship = create(:sponsorship)
      item = create(:sponsors_subscription_item)

      result = Sponsors::AddOneTimePayments::Result.new(sponsorships: [sponsorship], subscription_items: [item])

      assert_equal [sponsorship.sponsorable, item.sponsorable], result.sponsorables
    end
  end

  context "#sponsorships" do
    test "returns given list of sponsorships" do
      sponsorship = Sponsorship.new
      result = Sponsors::AddOneTimePayments::Result.new(sponsorships: [sponsorship])
      assert_equal [sponsorship], result.sponsorships
    end
  end

  context "#subscription_items" do
    test "returns given list of subscription items" do
      sub_item1 = Billing::SubscriptionItem.new
      sub_item2 = Billing::SubscriptionItem.new
      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [sub_item1, sub_item2])
      assert_equal [sub_item1, sub_item2], result.subscription_items
    end
  end

  context "#any_sponsored_organizations?" do
    test "returns true if any of the sponsorships are for an organization" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [], sponsorships: [sponsorship])
      assert_predicate result, :any_sponsored_organizations?
    end

    test "returns true if any of the subscription items are for an organization" do
      listing = create(:sponsors_listing, :approved, :for_org, tier_count: 1)
      tier = listing.default_tier
      sponsorship = create(:sponsorship, tier: tier)
      item = sponsorship.subscription_item

      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [item], sponsorships: [])

      assert_predicate result, :any_sponsored_organizations?
    end

    test "returns false when no subscription items or sponsorships are for an organization" do
      sponsorship = create(:sponsorship)
      sub_item = create(:sponsors_subscription_item)

      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [sub_item], sponsorships: [sponsorship])

      refute_predicate result, :any_sponsored_organizations?
    end
  end

  context "#any_sponsored_users?" do
    test "returns true if any of the sponsorships are for a user" do
      sponsorship = create(:sponsorship)
      assert_predicate sponsorship.sponsorable, :user?
      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [], sponsorships: [sponsorship])
      assert_predicate result, :any_sponsored_users?
    end

    test "returns true if any of the subscription items are for a user" do
      item = create(:sponsors_subscription_item)
      assert_predicate item.subscribable.sponsorable, :user?
      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [item], sponsorships: [])
      assert_predicate result, :any_sponsored_users?
    end

    test "returns false when no subscription items or sponsorships are for a user" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      listing = create(:sponsors_listing, :approved, :for_org, tier_count: 1)
      tier = listing.default_tier
      item = create(:sponsorship, tier: tier).subscription_item

      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [item], sponsorships: [sponsorship])

      refute_predicate result, :any_sponsored_users?
    end
  end

  context "#total_sponsored" do
    test "returns how many subscription items and sponsorships were created" do
      sub_item = Billing::SubscriptionItem.new
      sponsorship1 = Sponsorship.new
      sponsorship2 = Sponsorship.new

      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [sub_item],
        sponsorships: [sponsorship1, sponsorship2])

      assert_equal 3, result.total_sponsored
    end
  end

  context "#total_amount_excluding_fees" do
    test "returns the sum of sponsorship and subscription item amounts" do
      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 5_00)
      sub_item = create(:sponsors_subscription_item, subscribable: tier)
      sponsorship1 = create(:sponsorship, monthly_price_in_cents: 10_00)
      sponsorship2 = create(:sponsorship, monthly_price_in_cents: 3_00)

      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [sub_item],
        sponsorships: [sponsorship1, sponsorship2])

      assert_equal Billing::Money.new(18_00), result.total_amount_excluding_fees
    end

    test "excludes fees from total" do
      cc_org = create(:credit_card_organization)
      tier = create(:sponsors_tier, :published, monthly_price_in_cents: 5_00)
      sub_item = create(:sponsors_subscription_item, account: cc_org, subscribable: tier)
      sponsorship1 = create(:sponsorship, sponsor: cc_org, monthly_price_in_cents: 10_00)
      sponsorship2 = create(:sponsorship, sponsor: cc_org, monthly_price_in_cents: 3_00)

      sub_item_fee = sub_item.sponsors_fee(sub_item.base_price).cents
      assert_operator sub_item_fee, :>=, 0

      result = Sponsors::AddOneTimePayments::Result.new(subscription_items: [sub_item],
        sponsorships: [sponsorship1, sponsorship2])

      assert_equal Billing::Money.new(18_00), result.total_amount_excluding_fees
    end
  end

  context "#success?" do
    test "returns true when errors is empty" do
      result = Sponsors::AddOneTimePayments::Result.new(errors: [])
      assert_predicate result, :success?
    end

    test "returns false when errors is not empty" do
      result = Sponsors::AddOneTimePayments::Result.new(errors: ["error 1"])
      refute_predicate result, :success?
    end
  end
end
