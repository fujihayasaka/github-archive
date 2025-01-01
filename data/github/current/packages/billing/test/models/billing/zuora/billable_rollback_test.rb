# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::BillableRollbackTest < GitHub::BillingTestCase
  include AuditLogHelpers
  include GitHub::SponsorsZuoraTestHelper
  include HydroTestHelpers

  setup { FakeZuora.mock }

  context "#perform" do
    test "audit logs rollbacks" do
      item = create :billing_subscription_item
      item.subscribable.sync_to_zuora
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
      test_error = "Hello I am a rollback"

      events = subscribe "billing.billable_rollback"

      Billing::Zuora::BillableRollback.perform item.plan_subscription, test_error

      assert_equal 1, events.size
      event = events.first
      assert_equal "billing.billable_rollback", event.name
      assert_equal item.user.login, event.payload[:user]
      assert_equal item.user.id, event.payload[:user_id]
      assert_equal test_error, event.payload[:error]
    end

    test "records datadog metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      item = create :billing_subscription_item
      item.subscribable.sync_to_zuora
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
      test_error = "Hello I am a rollback"

      Billing::Zuora::BillableRollback.perform item.plan_subscription, test_error

      refute_empty GitHub.dogstats.increments(
        "billing.billable_rollback",
        tags: ["action:cancel", "subscribable_type:#{item.subscribable_type}"]
      )
    end

    test "records sponsorship rollback for user notification" do
      item = create :sponsors_subscription_item
      create(:billing_product_uuid, :sponsors_listing, listing: item.listing)
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      refute_predicate item.user, :has_sponsorship_rollback?

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      assert_predicate item.user, :has_sponsorship_rollback?
    end

    test "resets the sponsorship rollback notice for user notification" do
      item = create :sponsors_subscription_item
      create(:billing_product_uuid, :sponsors_listing, listing: item.listing)
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      item.user.dismiss_notice(:sponsorship_rollback)

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      refute item.user.dismissed_notice?(:sponsorship_rollback)
    end

    test "does not record non-sponsorship rollback for user notification" do
      item = create :billing_subscription_item, :paid
      item.subscribable.sync_to_zuora
      fake_sub = stub "zuora_subscription",
        active_rate_plans: []
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      refute_predicate item.user, :has_sponsorship_rollback?

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      refute_predicate item.user, :has_sponsorship_rollback?
    end

    test "cancels new marketplace subscription items" do
      item = create :billing_subscription_item
      item.subscribable.sync_to_zuora
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).with "billing.billable_rollback", user: item.user, error: "error"

      GitHub.expects(:instrument).with "marketplace_purchase.cancelled",
        subscription_item_id: item.id,
        sender_id: item.user.id,
        previous_quantity: item.quantity,
        previous_subscribable_id: item.subscribable.id,
        previous_subscribable_type: item.subscribable.class.name
      Billing::PlanSubscription::SendFailureNotification.expects(:perform).with \
        item.plan_subscription,
        marketplace: true,
        message: "error"

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      assert_predicate item.reload, :cancelled?
    end

    test "cancels new sponsorable items" do
      sponsorship = create(:sponsorship)
      sponsor = sponsorship.sponsor
      sponsor_item = sponsorship.subscription_item
      sponsorable = sponsorship.sponsorable
      create(:billing_product_uuid, :sponsors_listing, listing: sponsor_item.listing)
      plan_subscription = sponsor_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
      events = subscribe "sponsors.sponsor_sponsorship_cancel"
      expected_payload = {
        actor: sponsor.login,
        actor_id: sponsor.id,
        user: sponsor.login,
        user_id: sponsor.id,
        sponsorable_user: sponsorable.login,
        sponsorable_user_id: sponsorable.id,
        sponsorship_id: sponsorship.id,
        current_tier_id: sponsor_item.subscribable.id,
        current_tier_monthly_amount_in_cents: sponsorship.monthly_price_in_cents,
        active: false,
        sponsor: sponsor.login,
        sponsor_id: sponsor.id,
        public: true,
        frequency: "recurring",
        payment_source: "github",
      }

      GitHub.expects(:instrument).with "billing.billable_rollback", user: sponsor_item.user, error: "error"

      GitHub.expects(:instrument).with "sponsorship.cancelled",
        subscription_item_id: sponsor_item.id,
        sender_id: sponsor_item.user.id,
        previous_quantity: sponsor_item.quantity,
        previous_subscribable_id: sponsor_item.subscribable.id,
        previous_subscribable_type: sponsor_item.subscribable.class.name
      Billing::PlanSubscription::SendFailureNotification.expects(:perform).with \
        sponsor_item.plan_subscription,
        marketplace: true,
        message: "error"

      Billing::Zuora::BillableRollback.perform sponsor_item.plan_subscription, "error"

      assert_predicate sponsor_item.reload, :cancelled?
      refute_predicate sponsorship.reload, :active?
      refute_nil event = events.pop, "an audit log event was expected"
      assert_equal expected_payload, event.payload
    end

    test "cancels one_time sponsorable items" do
      sponsorship = create(:sponsorship, :one_time)
      sponsorable = sponsorship.sponsorable
      sponsor = sponsorship.sponsor
      sponsor_item = sponsorship.subscription_item
      tier = sponsorship.tier
      listing = tier.sponsors_listing
      create(:billing_product_uuid, :sponsors_listing, :one_time, listing: listing)

      plan_subscription = sponsor_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      events = subscribe "sponsors.sponsor_sponsorship_cancel"
      expected_payload = {
        actor: sponsor.login,
        actor_id: sponsor.id,
        user: sponsor.login,
        user_id: sponsor.id,
        sponsorable_user: sponsorable.login,
        sponsorable_user_id: sponsorable.id,
        sponsorship_id: sponsorship.id,
        current_tier_id: sponsor_item.subscribable.id,
        current_tier_monthly_amount_in_cents: sponsorship.monthly_price_in_cents,
        active: false,
        sponsor: sponsor.login,
        sponsor_id: sponsor.id,
        public: true,
        frequency: "one_time",
        payment_source: "github",
      }

      GitHub.expects(:instrument).with "billing.billable_rollback", user: sponsor_item.user, error: "error"

      GitHub.expects(:instrument).with "sponsorship.cancelled",
        subscription_item_id: sponsor_item.id,
        sender_id: sponsor_item.user.id,
        previous_quantity: sponsor_item.quantity,
        previous_subscribable_id: tier.id,
        previous_subscribable_type: tier.class.name
      Billing::PlanSubscription::SendFailureNotification.expects(:perform).with \
        sponsor_item.plan_subscription,
        marketplace: true,
        message: "error"

      Billing::Zuora::BillableRollback.perform sponsor_item.plan_subscription, "error"

      assert_predicate sponsor_item.reload, :cancelled?
      refute_predicate sponsorship.reload, :active?
      refute_nil event = events.pop, "an audit log event was expected"
      assert_equal expected_payload, event.payload
    end

    test "cancels failed additional one-time sponsorship to the same maintainer" do
      user = zuora_user_sponsor
      plan_subscription = sponsors_plan_subscription(user)
      listing = billing_enabled_sponsors_listing
      tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
      one_time_date = GitHub::Billing.today - (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days

      travel_to(one_time_date) do
        initial_sponsorship = ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)
        # fake out the payment process that deactivates the related subscription item
        initial_sponsorship.subscription_item.deactivate_without_callbacks
      end

      sponsorship = ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)
      sponsor_item = sponsorship.subscription_item

      stub_sponsors_subscription(
        plan_subscription: plan_subscription,
        rate_plans: [
          one_time_sponsorship_rate_plan(
            tier: tier,
            sponsor: user,
            added_at_date: one_time_date,
          )
        ],
      )

      Billing::PlanSubscription::SendFailureNotification.expects(:perform).with \
        plan_subscription,
        marketplace: true,
        message: "error"

      Billing::Zuora::BillableRollback.perform plan_subscription, "error"

      assert_predicate sponsor_item.reload, :cancelled?
      # N.B. Ideally we would recognize that the recent one-time sponorship is still valid and
      # instead of cancelling the sponsorship, restor the previous state. Sponsorship mutability
      # currently makes this difficult.
      refute_predicate sponsorship.reload, :active?
    end

    test "cancels new sponsorships for enterprise account member orgs" do
      sub_item = create(:sponsors_subscription_item, :self_serve_business)
      business = sub_item.account
      business.update_billing_date(next_billing_date: GitHub::Billing.today, billing_attempts: 0)
      tier = sub_item.subscribable
      listing = sub_item.listing
      sponsor = sub_item.organization
      sponsorable = listing.sponsorable
      sponsorship = create(:sponsorship,
        sponsor: sponsor,
        sponsorable: sponsorable,
        tier: tier,
        subscription_item: sub_item
      )

      create(:billing_product_uuid, :sponsors_listing, listing: sub_item.listing)
      plan_subscription = sub_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
      events = subscribe "sponsors.sponsor_sponsorship_cancel"
      expected_payload = {
        actor: sponsor.login,
        actor_id: sponsor.id,
        org: sponsor.login,
        org_id: sponsor.id,
        sponsorable_user: sponsorable.login,
        sponsorable_user_id: sponsorable.id,
        sponsorship_id: sponsorship.id,
        current_tier_id: sub_item.subscribable.id,
        current_tier_monthly_amount_in_cents: sponsorship.monthly_price_in_cents,
        active: false,
        sponsor: sponsor.login,
        sponsor_id: sponsor.id,
        public: true,
        frequency: "recurring",
        payment_source: "github",
      }

      GitHub.expects(:instrument).with "billing.billable_rollback", user: sub_item.user, error: "error"

      GitHub.expects(:instrument).with "sponsorship.cancelled",
        subscription_item_id: sub_item.id,
        sender_id: sponsor.id,
        previous_quantity: sub_item.quantity,
        previous_subscribable_id: sub_item.subscribable.id,
        previous_subscribable_type: sub_item.subscribable.class.name
      Billing::PlanSubscription::SendFailureNotification.expects(:perform).with \
        sub_item.plan_subscription,
        marketplace: true,
        message: "error"

      Billing::Zuora::BillableRollback.perform sub_item.plan_subscription, "error"

      assert_predicate sub_item.reload, :cancelled?
      refute_predicate sponsorship.reload, :active?
      refute_nil event = events.pop, "an audit log event was expected"
      assert_equal expected_payload, event.payload
    end

    test "generates a hydro event for cancelled sponsorships" do
      sponsorship = create(:sponsorship)
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")

      sponsor = sponsorship.sponsor
      sponsor_item = sponsorship.subscription_item
      listing = sponsor_item.listing
      create(:billing_product_uuid, :sponsors_listing, listing: listing)
      plan_subscription = sponsor_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      Billing::Zuora::BillableRollback.perform sponsor_item.plan_subscription, "error"

      message = {
        actor: Hydro::EntitySerializer.user(sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsor_item.subscribable),
        action: :CANCEL,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }

      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "generates a Hydro event for cancelled sponsorship request" do
      sponsorship = create(:sponsorship)

      sponsor = sponsorship.sponsor
      sponsor_item = sponsorship.subscription_item
      listing = sponsor_item.listing
      create(:billing_product_uuid, :sponsors_listing, listing: listing)
      plan_subscription = sponsor_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      Billing::Zuora::BillableRollback.perform sponsor_item.plan_subscription, "error"

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(sponsor),
        sponsor: Hydro::EntitySerializer.user(sponsor),
        sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
        reason: :BILLABLE_ROLLBACK,
        forced: true
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "doesn't cancel new copilot subscription items" do
      item = create :billing_subscription_item, :with_product_uuid
      fake_sub = stub "zuora_subscription",
        active_rate_plans: []
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: item.user, error: "error"

      Billing::PlanSubscription::SendFailureNotification.expects(:perform).never

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      refute_predicate item.reload, :cancelled?
    end

    test "doesn't cancel exiting copilot subscription items" do
      item = create :billing_subscription_item, :with_product_uuid
      fake_sub = stub "zuora_subscription",
        active_rate_plans: [
          { productRatePlanId: item.subscribable.zuora_product_rate_plan_id },
        ]
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: item.user, error: "error"

      Billing::PlanSubscription::SendFailureNotification.expects(:perform).never

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      refute_predicate item.reload, :cancelled?
    end

    test "doesn't cancel existing marketplace subscription items" do
      item = create :billing_subscription_item
      item.subscribable.sync_to_zuora
      rate_plan = ::Billing::Zuora::RatePlan.new(
        productRatePlanId: item.subscribable.zuora_id(cycle: item.user.plan_duration)
      )
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns([rate_plan])
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: item.user, error: "error"

      Billing::PlanSubscription::SendFailureNotification.expects(:perform).never

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      refute_predicate item.reload, :cancelled?
    end

    test "doesn't cancel existing tier-based sponsorable items" do
      sponsor_item = create :sponsors_subscription_item
      sponsors_tier = sponsor_item.subscribable
      sponsors_listing = sponsors_tier.sponsors_listing
      tier_uuid = create(:billing_product_uuid, :sponsors_tier, tier: sponsors_tier)
      create(:billing_product_uuid, :sponsors_listing, listing: sponsors_listing)
      rate_plan = ::Billing::Zuora::RatePlan.new(
        productRatePlanId: tier_uuid.zuora_product_rate_plan_id
      )
      plan_subscription = sponsor_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns([rate_plan])

      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: sponsor_item.user, error: "error"
      Billing::PlanSubscription::SendFailureNotification.expects(:perform).never

      Billing::Zuora::BillableRollback.perform sponsor_item.plan_subscription, "error"

      refute_predicate sponsor_item.reload, :cancelled?
    end

    test "doesn't cancel existing listing-based sponsorable items" do
      sponsor_item = create :sponsors_subscription_item
      sponsors_tier = sponsor_item.subscribable
      sponsors_listing = sponsors_tier.sponsors_listing
      create(:billing_product_uuid, :sponsors_tier, tier: sponsors_tier)
      listing_uuid = create(:billing_product_uuid, :sponsors_listing, listing: sponsors_listing)
      rate_plan = ::Billing::Zuora::RatePlan.new(
        productRatePlanId: listing_uuid.zuora_product_rate_plan_id,
      )
      plan_subscription = sponsor_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns([rate_plan])
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: sponsor_item.user, error: "error"
      Billing::PlanSubscription::SendFailureNotification.expects(:perform).never

      Billing::Zuora::BillableRollback.perform sponsor_item.plan_subscription, "error"

      refute_predicate sponsor_item.reload, :cancelled?
    end

    test "resets quantity of existing subscription items" do
      listing_plan = create :marketplace_listing_plan, :per_unit,
        listing: create(:marketplace_listing, :verified),
        state: :published
      item = create :billing_subscription_item,
        subscribable: listing_plan,
        quantity: 4
      item.subscribable.sync_to_zuora
      rate_plan = ::Billing::Zuora::RatePlan.new(
        productRatePlanId: item.subscribable.zuora_id(cycle: item.user.plan_duration),
        ratePlanCharges: [
          {
            quantity: 2,
          },
        ],
      )
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns([rate_plan])
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.stubs(:instrument)
      GitHub.expects(:instrument).with "marketplace_purchase.changed",
        subscription_item_id: item.id,
        sender_id: item.user.id,
        previous_quantity: item.quantity,
        previous_subscribable_id: item.subscribable.id,
        previous_subscribable_type: item.subscribable.class.name

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      assert_equal 2, item.reload.quantity
    end

    test "doesn't reset existing subscription items" do
      listing_plan = create :marketplace_listing_plan, :per_unit,
        listing: create(:marketplace_listing, :verified),
        state: :published
      item = create :billing_subscription_item,
        subscribable: listing_plan,
        quantity: 4
      item.subscribable.sync_to_zuora
      item.user.update plan: GitHub::Plan.pro
      item.user.plan.sync_to_zuora
      active_rate_plans = [
        {
          productRatePlanId: item.user.plan.zuora_id(cycle: item.user.plan_duration),
        },
        {
          productRatePlanId: item.subscribable.zuora_id(cycle: item.user.plan_duration),
          ratePlanCharges: [
            {
              quantity: 4,
            },
          ],
        },
      ].map { |attrs| ::Billing::Zuora::RatePlan.new(attrs) }
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: item.user, error: "error"

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      assert_equal 4, item.reload.quantity
    end

    test "doesn't reset existing sponsorable subscription items" do
      item = create :sponsors_subscription_item,
        quantity: 1
      listing = item.listing
      create(:billing_product_uuid, :sponsors_listing, listing: listing)
      item.user.update plan: GitHub::Plan.pro
      item.user.plan.sync_to_zuora
      active_rate_plans = [
        {
          productRatePlanId: item.user.plan.zuora_id(cycle: item.user.plan_duration),
        },
        {
          productRatePlanId: listing.zuora_rate_plan_id(billing_cycle: item.user.plan_duration),
          ratePlanCharges: [
            {
              quantity: 1,
            },
          ],
        },
      ].map { |attrs| ::Billing::Zuora::RatePlan.new(attrs) }
      plan_subscription = item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      GitHub.expects(:instrument).once.with "billing.billable_rollback", user: item.user, error: "error"

      Billing::Zuora::BillableRollback.perform item.plan_subscription, "error"

      assert_equal 1, item.reload.quantity
    end

    test "doesn't cancel recurring sponsorship if adding concurrent one-time payment fails" do
      recurring_sponsorship = create(:sponsorship)
      listing = recurring_sponsorship.sponsors_listing
      sponsor = recurring_sponsorship.sponsor
      recurring_tier = recurring_sponsorship.tier
      recurring_item = recurring_sponsorship.subscription_item
      one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

      one_time_item = create(:sponsors_subscription_item,
        plan_subscription: recurring_item.plan_subscription,
        subscribable: one_time_tier,
      )

      listing.sync_to_zuora
      recurring_tier_rate_plan_id = recurring_tier.listing_product_rate_plan_id(cycle: sponsor.plan_duration)
      rate_plan = ::Billing::Zuora::RatePlan.new(
        productRatePlanId: recurring_tier_rate_plan_id,
      )
      plan_subscription = recurring_item.plan_subscription
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_account_id, raw_subscription: {
        id: plan_subscription.zuora_subscription_id,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:active_rate_plans).returns([rate_plan])
      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

      # These events are in the Sponsors domain, and we don't want them to fire!
      sponsors_events = subscribe "sponsors.sponsor_sponsorship_cancel"

      # These events are in the Billing domain, and should still fire!
      GitHub.expects(:instrument).with "billing.billable_rollback", user: sponsor, error: "error"
      GitHub.expects(:instrument).with "sponsorship.cancelled",
        subscription_item_id: one_time_item.id,
        sender_id: one_time_item.user.id,
        previous_quantity: one_time_item.quantity,
        previous_subscribable_id: one_time_item.subscribable.id,
        previous_subscribable_type: one_time_item.subscribable.class.name

      Billing::PlanSubscription::SendFailureNotification.expects(:perform).with \
        recurring_item.plan_subscription,
        marketplace: true,
        message: "error"

      assert_predicate one_time_item, :active?, "we need an active item to roll back"

      Billing::Zuora::BillableRollback.perform recurring_item.plan_subscription, "error"

      assert_predicate one_time_item.reload, :cancelled?
      assert_predicate recurring_item.reload, :active?
      assert_predicate recurring_sponsorship.reload, :active?
      assert_nil sponsors_events.pop, "a Sponsors sponsorship cancellation audit log event should not exist"
    end
  end
end if GitHub.billing_enabled?
