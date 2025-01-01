# typed: true
# frozen_string_literal: true

require "test_helper"

class SendNowSponsoringViaBulkSponsorshipEmailJobTest < GitHub::TestCase
  include ActionMailer::TestHelper

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  fixtures do
    @sponsor = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
  end

  test "sends now_sponsoring_via_bulk_sponsorship email when sponsor and tiers paid are present for recurring tiers" do
    tier1 = create(:sponsors_tier, :approved_sponsors_listing, :recurring, monthly_price_in_cents: 1_00)
    tier2 = create(:sponsors_tier, :approved_sponsors_listing, :recurring, :for_org, monthly_price_in_cents: 5_00)
    tiers = [tier1, tier2]
    filename = "github-sponsors-bulk-sponsorship-for-#{@sponsor}-#{Time.now.strftime("%Y-%m-%d")}.csv"
    export_content = "Maintainer username,Sponsorship amount in USD\n#{tier1.sponsorable},$1 a month\n" \
      "#{tier2.sponsorable},$5 a month\n"

    SponsorsPrimerMailer.expects(:now_sponsoring_via_bulk_sponsorship).once.with(
      sponsor: @sponsor,
      total_amount: "$6",
      is_recurring: true,
      sponsorship_count: 2,
      any_sponsored_users: true,
      any_sponsored_organizations: true,
      filename: filename,
      export_content: export_content,
    ).returns(stub(deliver_later: nil))

    SendNowSponsoringViaBulkSponsorshipEmailJob.perform_now(
      sponsor: @sponsor,
      tiers_paid: tiers,
    )
  end

  test "sends now_sponsoring_via_bulk_sponsorship email when sponsor and tiers paid are present for one-time tiers" do
    tier1 = create(:sponsors_tier, :approved_sponsors_listing, :one_time, monthly_price_in_cents: 1_00)
    tier2 = create(:sponsors_tier, :approved_sponsors_listing, :one_time, :for_org, monthly_price_in_cents: 3_00)
    tiers = [tier1, tier2]
    filename = "github-sponsors-bulk-sponsorship-for-#{@sponsor}-#{Time.now.strftime("%Y-%m-%d")}.csv"
    export_content = "Maintainer username,Sponsorship amount in USD\n#{tier1.sponsorable},$1 one time\n" \
      "#{tier2.sponsorable},$3 one time\n"

    SponsorsPrimerMailer.expects(:now_sponsoring_via_bulk_sponsorship).once.with(
      sponsor: @sponsor,
      total_amount: "$4",
      is_recurring: false,
      sponsorship_count: 2,
      any_sponsored_users: true,
      any_sponsored_organizations: true,
      filename: filename,
      export_content: export_content,
    ).returns(stub(deliver_later: nil))

    SendNowSponsoringViaBulkSponsorshipEmailJob.perform_now(
      sponsor: @sponsor,
      tiers_paid: tiers,
    )
  end

  test "does not send now_sponsoring_via_bulk_sponsorship email when tiers paid are not present" do
    SponsorsPrimerMailer.expects(:now_sponsoring_via_bulk_sponsorship).never

    SendNowSponsoringViaBulkSponsorshipEmailJob.perform_now(
      sponsor: @sponsor,
      tiers_paid: [],
    )
  end
end
