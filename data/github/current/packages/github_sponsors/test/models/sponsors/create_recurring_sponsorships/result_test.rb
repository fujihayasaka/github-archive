# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::CreateRecurringSponsorships::ResultTest < GitHub::TestCase
  context "#errors" do
    test "returns given list of errors" do
      result = Sponsors::CreateRecurringSponsorships::Result.new(errors: ["error 1", "error 2"])
      assert_equal ["error 1", "error 2"], result.errors
    end
  end

  context "#sponsorables" do
    test "returns list of sponsorables from given sponsorships" do
      sponsorship1, sponsorship2 = create_pair(:sponsorship)

      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship1, sponsorship2])

      assert_equal [sponsorship1.sponsorable, sponsorship2.sponsorable], result.sponsorables
    end
  end

  context "#sponsorships" do
    test "returns given list of sponsorships" do
      sponsorship = Sponsorship.new
      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship])
      assert_equal [sponsorship], result.sponsorships
    end
  end

  context "#any_sponsored_organizations?" do
    test "returns true if any of the sponsorships are for an organization" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship])
      assert_predicate result, :any_sponsored_organizations?
    end

    test "returns false when no sponsorships are for an organization" do
      sponsorship = create(:sponsorship)
      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship])
      refute_predicate result, :any_sponsored_organizations?
    end
  end

  context "#any_sponsored_users?" do
    test "returns true if any of the sponsorships are for a user" do
      sponsorship = create(:sponsorship)
      assert_predicate sponsorship.sponsorable, :user?

      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship])

      assert_predicate result, :any_sponsored_users?
    end

    test "returns false when no sponsorships are for a user" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship])
      refute_predicate result, :any_sponsored_users?
    end
  end

  context "#total_sponsored" do
    test "returns how many sponsorships were created" do
      sponsorship1 = Sponsorship.new
      sponsorship2 = Sponsorship.new

      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship1, sponsorship2])

      assert_equal 2, result.total_sponsored
    end
  end

  context "#total_amount_excluding_fees" do
    test "returns the sum of sponsorship amounts" do
      sponsorship1 = create(:sponsorship, monthly_price_in_cents: 10_00)
      sponsorship2 = create(:sponsorship, monthly_price_in_cents: 3_00)

      result = Sponsors::CreateRecurringSponsorships::Result.new(sponsorships: [sponsorship1, sponsorship2])

      assert_equal Billing::Money.new(13_00), result.total_amount_excluding_fees
    end
  end

  context "#success?" do
    test "returns true when errors is empty" do
      result = Sponsors::CreateRecurringSponsorships::Result.new(errors: [])
      assert_predicate result, :success?
    end

    test "returns false when errors is not empty" do
      result = Sponsors::CreateRecurringSponsorships::Result.new(errors: ["error 1"])
      refute_predicate result, :success?
    end
  end
end
