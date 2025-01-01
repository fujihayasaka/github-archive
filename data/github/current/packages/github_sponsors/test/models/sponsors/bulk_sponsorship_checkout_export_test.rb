# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::BulkSponsorshipCheckoutExportTest < GitHub::TestCase
  fixtures do
    @sponsor = create(:credit_card_user, :verified,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons
    )
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#filename" do
    test "returns filename with sponsor login and local date if sponsor has no timezone" do
      now = Time.now
      date = now.strftime("%Y-%m-%d")
      export = Timecop.freeze(now) do
        Sponsors::BulkSponsorshipCheckoutExport.new(sponsor: @sponsor, tiers_paid: [])
      end

      assert_equal "github-sponsors-bulk-sponsorship-for-#{@sponsor.login}-#{date}.csv", export.filename
    end

    test "returns filename with sponsor login and current date in sponsor's timezone if present" do
      sponsor = create(:credit_card_user, :verified, time_zone_name: "Europe/Madrid")

      now = Time.now.in_time_zone("Europe/Madrid")
      date = now.strftime("%Y-%m-%d")
      export = Timecop.freeze(now) do
        Sponsors::BulkSponsorshipCheckoutExport.new(sponsor: sponsor, tiers_paid: [])
      end

      assert_equal "github-sponsors-bulk-sponsorship-for-#{sponsor.login}-#{date}.csv", export.filename
    end
  end

  context "#as_csv" do
    test "returns details for tiers" do
      tier_1 = create(:sponsors_tier, :recurring, :published, monthly_price_in_cents: 1_00)
      tier_2 = create(:sponsors_tier, :one_time, :published, :custom, monthly_price_in_cents: 3_00)
      tiers = [tier_1, tier_2]

      expected_sponsorship_1 = [
        tier_1.sponsorable_login,
        "$1 a month",
      ].join(",")
      expected_sponsorship_2 = [
        tier_2.sponsorable_login,
        "$3 one time",
      ].join(",")

      expected_csv = <<~CSV
        #{Sponsors::BulkSponsorshipCheckoutExport::HEADERS.join(",")}
        #{expected_sponsorship_1}
        #{expected_sponsorship_2}
      CSV

      export = Sponsors::BulkSponsorshipCheckoutExport.new(
        sponsor: @sponsor,
        tiers_paid: tiers
      )

      assert_equal expected_csv, export.as_csv
    end

    test "returns correct frequency for yearly billed sponsors" do
      yearly_sponsor = create(:credit_card_user, plan_duration: "year")

      tier = create(:sponsors_tier, :recurring, :published, monthly_price_in_cents: 1_00)
      tiers = [tier]

      expected_sponsorship = [
        tier.sponsorable_login,
        "$12 a year",
      ].join(",")

      expected_csv = <<~CSV
        #{Sponsors::BulkSponsorshipCheckoutExport::HEADERS.join(",")}
        #{expected_sponsorship}
      CSV

      export = Sponsors::BulkSponsorshipCheckoutExport.new(
        sponsor: yearly_sponsor,
        tiers_paid: tiers
      )

      assert_equal expected_csv, export.as_csv
    end
  end
end
