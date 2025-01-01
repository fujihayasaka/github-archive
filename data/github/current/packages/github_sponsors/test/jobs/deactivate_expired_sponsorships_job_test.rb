# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeactivateExpiredSponsorshipsJobTest < GitHub::TestCase
  include HydroTestHelpers

  skip_unless :sponsors_enabled?

  fixtures do
    @non_expired_one_time_sponsorship = create(:sponsorship, :one_time)
    @recurring_sponsorship = create(:sponsorship)
    @expired_invoiced_sponsorship = create(:sponsorship, :invoiced,
      expires_at: Date.current - 1.day)
    @non_expired_invoiced_sponsorship = create(:sponsorship, :invoiced,
      expires_at: Date.current + 1.day)
  end

  setup do
    @expired_one_time_sponsorship =
      travel_to((Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS + 1).days.ago) do
        create(:sponsorship, :one_time)
      end
  end

  context "#perform" do
    test "marks expired one-time sponsorships as inactive" do
      assert_predicate @expired_one_time_sponsorship, :expired?
      refute_predicate @non_expired_one_time_sponsorship, :expired?
      assert_predicate @expired_one_time_sponsorship, :active?
      assert_predicate @non_expired_one_time_sponsorship, :active?

      DeactivateExpiredSponsorshipsJob.perform_now

      refute_predicate @expired_one_time_sponsorship.reload, :active?
      assert_predicate @non_expired_one_time_sponsorship.reload, :active?
    end

    test "deactivates one-time sponsorships' subscription items" do
      assert_predicate @expired_one_time_sponsorship, :expired?
      refute_predicate @non_expired_one_time_sponsorship, :expired?
      assert_predicate @expired_one_time_sponsorship.subscription_item, :active?
      assert_predicate @non_expired_one_time_sponsorship.subscription_item, :active?

      assert_difference "Billing::SubscriptionItem.active.count", -1 do
        DeactivateExpiredSponsorshipsJob.perform_now
      end

      refute_predicate @expired_one_time_sponsorship.reload_subscription_item, :active?
      assert_predicate @non_expired_one_time_sponsorship.reload_subscription_item, :active?
    end

    test "marks expired invoiced sponsorships as inactive" do
      assert_predicate @expired_invoiced_sponsorship, :expired?
      refute_predicate @non_expired_invoiced_sponsorship, :expired?
      assert_predicate @expired_invoiced_sponsorship, :active?
      assert_predicate @non_expired_invoiced_sponsorship, :active?

      DeactivateExpiredSponsorshipsJob.perform_now

      refute_predicate @expired_invoiced_sponsorship.reload, :active?
      assert_predicate @non_expired_invoiced_sponsorship.reload, :active?
    end

    test "ignores recurring sponsorships with nil expiration" do
      assert_nil @recurring_sponsorship.expires_at
      assert_predicate @recurring_sponsorship, :active?

      DeactivateExpiredSponsorshipsJob.perform_now

      assert_predicate @recurring_sponsorship.reload, :active?
      assert_predicate @recurring_sponsorship.reload_subscription_item, :active?
    end

    test "immediately cancels a Zuora-based recurring invoiced sponsorship and its subscription item" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsors_plan_sub = invoiced_org.sponsors_plan_subscription
      sponsorship = create(:sponsorship, sponsor: invoiced_org, expires_at: 1.day.ago)
      assert_predicate sponsorship, :recurring_payment?
      assert_equal sponsors_plan_sub, sponsorship.plan_subscription

      assert_no_difference(-> { Billing::PendingSubscriptionItemChange.count }) do
        DeactivateExpiredSponsorshipsJob.perform_now
      end

      refute_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :active?
    end

    test "instruments sponsorship cancellation request to Hydro when sponsorship frequency is recurring" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsors_plan_sub = invoiced_org.sponsors_plan_subscription
      sponsorship = create(:sponsorship, sponsor: invoiced_org, expires_at: 1.day.ago)

      reset_hydro
      DeactivateExpiredSponsorshipsJob.perform_now

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
        sponsor: Hydro::EntitySerializer.user(sponsorship.sponsor),
        sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
        reason: :EXPIRED_SPONSORSHIP,
        forced: true
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "does not instrument sponsorship cancellation request to Hydro when sponsorship frequency is one-time" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsors_plan_sub = invoiced_org.sponsors_plan_subscription
      sponsorship = create(:sponsorship, :one_time, sponsor: invoiced_org, expires_at: 1.day.ago)

      reset_hydro
      DeactivateExpiredSponsorshipsJob.perform_now

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end
  end
end
