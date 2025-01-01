# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsorship::InstrumentationDependencyTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers
  include StratocasterTestHelpers

  fixtures do
    @sponsorable = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @listing = create(:sponsors_listing, :approved, :with_stripe_account,
      sponsorable: @sponsorable
    )
    @recurring_tier = @listing.default_tier
    @sponsor = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @staff = create(:staff_admin_user)
  end

  context "#instrument_sponsorship_start" do
    test "emits sponsor.sponsor_sponsorship_create event" do
      events = subscribe("sponsors.sponsor_sponsorship_create")
      sponsorship = create(:sponsorship)
      sponsorship.instrument_sponsorship_start

      event = events.pop
      refute_nil event, "an event was expected"
      assert_equal sponsorship.sponsor_login, event.payload[:sponsor]
      assert_equal sponsorship.sponsor_login, event.payload[:user]
      assert_equal sponsorship.sponsor_login, event.payload[:actor]
      assert_equal sponsorship.sponsor_id, event.payload[:sponsor_id]
      assert_equal sponsorship.sponsor_id, event.payload[:user_id]
      assert_equal sponsorship.sponsor_id, event.payload[:actor_id]
      assert_equal sponsorship.id, event.payload[:sponsorship_id]
      assert_equal sponsorship.sponsorable_login, event.payload[:sponsorable_user]
      assert_equal sponsorship.sponsorable_id, event.payload[:sponsorable_user_id]
      assert_equal sponsorship.subscribable_id, event.payload[:current_tier_id]
      assert_equal sponsorship.tier.monthly_price_in_cents, event.payload[:current_tier_monthly_amount_in_cents]
      assert event.payload[:public]
      assert_equal "recurring", event.payload[:frequency]
      assert_equal "github", event.payload[:payment_source]
    end

    test "emits github.sponsors.v1.SponsorshipCreateCancel Hydro event" do
      sponsorship = create(:sponsorship, sponsorable: @listing.sponsorable)

      reset_hydro

      sponsorship.instrument_sponsorship_start

      message = {
        actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        matchable: false,
        action: :CREATE,
        first_time_sponsor: true,
        first_time_sponsorable: true,
        invoiced: false,
        payment_source: :GITHUB,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "emits sponsor.sponsor_sponsorship_create event for Patreon payment source" do
      events = subscribe("sponsors.sponsor_sponsorship_create")
      sponsorship = create(:sponsorship, :patreon)
      sponsorship.instrument_sponsorship_start

      event = events.pop
      refute_nil event, "an event was expected"
      assert_equal sponsorship.sponsor_login, event.payload[:sponsor]
      assert_equal sponsorship.sponsor_login, event.payload[:user]
      assert_equal sponsorship.sponsor_login, event.payload[:actor]
      assert_equal sponsorship.sponsor_id, event.payload[:sponsor_id]
      assert_equal sponsorship.sponsor_id, event.payload[:user_id]
      assert_equal sponsorship.sponsor_id, event.payload[:actor_id]
      assert_equal sponsorship.id, event.payload[:sponsorship_id]
      assert_equal sponsorship.sponsorable_login, event.payload[:sponsorable_user]
      assert_equal sponsorship.sponsorable_id, event.payload[:sponsorable_user_id]
      assert_equal sponsorship.subscribable_id, event.payload[:current_tier_id]
      assert_equal sponsorship.tier.monthly_price_in_cents, event.payload[:current_tier_monthly_amount_in_cents]
      assert event.payload[:public]
      assert_equal "recurring", event.payload[:frequency]
      assert_equal "patreon", event.payload[:payment_source]
    end

    test "includes Patreon payment source in Hydro event if newly created sponsor via Patreon" do
      sponsorship = create(:sponsorship, :patreon, sponsorable: @listing.sponsorable)

      reset_hydro

      sponsorship.instrument_sponsorship_start

      message = {
        actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        matchable: false,
        action: :CREATE,
        first_time_sponsor: true,
        first_time_sponsorable: true,
        invoiced: false,
        payment_source: :PATREON,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  context "#instrument_privacy_level_change" do
    if GitHub.sponsors_enabled?
      test "actor is guarded when they are GitHub staff" do
        sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)

        events = subscribe "sponsors.sponsor_sponsorship_edited"
        expected_payload = {
          active: true,
          public: sponsorship.privacy_public?,
          frequency: "recurring",
          current_tier_id: @recurring_tier.id,
          current_tier_monthly_amount_in_cents: @recurring_tier.monthly_price_in_cents,
          user: @sponsor.login,
          user_id: @sponsor.id,
          sponsorable_user: @sponsorable.login,
          sponsorable_user_id: @sponsorable.id,
          changes: { privacy_level: { from: "public" } },
          sponsor: @sponsor.login,
          sponsor_id: @sponsor.id,
          sponsorship_id: sponsorship.id,
          staff_actor: @staff.login,
          staff_actor_id: @staff.id,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
          payment_source: "github",
        }

        sponsorship.instrument_privacy_level_change(actor: @staff, previous_privacy_level: "public")

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end

    test "actor is not guarded when they are not GitHub staff" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)

      events = subscribe "sponsors.sponsor_sponsorship_edited"
      expected_payload = {
        active: true,
        public: sponsorship.privacy_public?,
        frequency: "recurring",
        current_tier_id: @recurring_tier.id,
        current_tier_monthly_amount_in_cents: @recurring_tier.monthly_price_in_cents,
        user: @sponsor.login,
        user_id: @sponsor.id,
        sponsorable_user: @sponsorable.login,
        sponsorable_user_id: @sponsorable.id,
        changes: { privacy_level: { from: "public" } },
        sponsor: @sponsor.login,
        sponsor_id: @sponsor.id,
        sponsorship_id: sponsorship.id,
        actor: @sponsor.login,
        actor_id: @sponsor.id,
        payment_source: "github",
      }

      sponsorship.instrument_privacy_level_change(actor: @sponsor, previous_privacy_level: "public")

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#instrument_restoration" do
    test "sends sponsors.sponsor_sponsorship_restoration event" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      tier = sponsorship.tier
      expected_payload = {
        sponsorable_user: @sponsorable.login,
        sponsorable_user_id: @sponsorable.id,
        sponsor: @sponsor.login,
        sponsor_id: @sponsor.id,
        sponsorship_id: sponsorship.id,
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      events = assert_performed_audit_entries(count: 1, only: "sponsors.sponsor_sponsorship_restore") do
        sponsorship.instrument_restoration(actor: @staff)
      end

      assert_equal last_performed_audit_entries, events
      assert_subset_hash expected_payload, events.first
    end
  end

  context "#instrument_transfer_failure" do
    test "sends sponsor.sponsor_sponsorship_transfer_failed event" do
      billing_line_items = [create(:billing_transaction_line_item, :sponsors, :with_sponsorship)]
      line_item = billing_line_items.first
      sponsorship = line_item.sponsorship
      stripe_account = create(:stripe_connect_account, sponsors_listing: line_item.sponsors_listing)
      reason = "Bad currency code"

      sponsorship.instrument_transfer_failure(billing_line_items: billing_line_items, reason: reason)

      GitHub.dogstats.increment("stripe.transfer.failed")
      assert_dogstats_increment(1, "stripe.transfer.failed")

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTransferFailure")
      message = hydro_messages(schema: "github.sponsors.v1.SponsorshipTransferFailure").first
      assert_equal reason, message[:reason]
      assert_equal line_item.amount_in_cents, message[:amount_in_cents]
      # The next two tests look for matching IDs because the serializer returns a truncated object
      assert_equal line_item.sponsors_listing.id, message[:listing][:id]
      assert_equal sponsorship.id, message[:sponsorship][:id]
      assert_equal line_item.sponsors_stripe_transfer_account_id, message[:stripe_account_id]
      assert_equal line_item.billing_transaction_id, message[:billing_transaction_id]
      assert_equal Hydro::EntitySerializer.stripe_connect_account(stripe_account), message[:stripe_connect_account]
    end
  end

  context "#instrument_cancel_request" do
    test "sends sponsors.sponsorship_cancel_request event when sponsorship frequency is recurring" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorship.instrument_cancel_request(reason: :SPONSOR_INITIATED, force: true, actor: @sponsor)

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(@sponsor),
        sponsor: Hydro::EntitySerializer.user(@sponsor),
        sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
        reason: :SPONSOR_INITIATED,
        forced: true,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "does not send sponsors.sponsorship_cancel_request event when sponsorship frequency is one-time" do
      sponsorship = create(:sponsorship, :one_time, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorship.instrument_cancel_request(reason: :SPONSOR_INITIATED, force: false)

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "sends sponsors.sponsorship_cancel_request event with UKNOWN reason when the given is invalid" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorship.instrument_cancel_request(reason: :NO_DINERO, force: false, actor: @sponsor)

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(@sponsor),
        sponsor: Hydro::EntitySerializer.user(@sponsor),
        sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
        reason: :UNKNOWN,
        forced: false,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "sends sponsors.sponsorship_cancel_request event when sponsorship is invoiced manual and recurring" do
      transfer1 = create(:invoiced_sponsorship_transfer, :completed)
      transfer2 = travel_to(transfer1.created_at + Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days) do
        create(:invoiced_sponsorship_transfer, :completed, sponsor: transfer1.sponsor,
          sponsors_listing: transfer1.sponsors_listing)
      end
      sponsorship = transfer2.sponsorship

      assert_predicate transfer2, :consecutive_recurrence?
      refute_predicate sponsorship, :recurring_payment?

      sponsorship.instrument_cancel_request(reason: :SPONSOR_INITIATED, force: false, actor: sponsorship.sponsor)

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
        reason: :SPONSOR_INITIATED,
        forced: false,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "does not send sponsors.sponsorship_cancel_request event when sponsorship is invoiced manual and one-time" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      sponsorship = transfer.sponsorship

      refute_predicate transfer, :consecutive_recurrence?
      refute_predicate sponsorship, :recurring_payment?

      sponsorship.instrument_cancel_request(reason: :SPONSOR_INITIATED, force: false)

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "sends sponsors.sponsorship_cancel_request with given actor when argument is defined" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorship.instrument_cancel_request(reason: :SPONSOR_INITIATED, force: true, actor: User.staff_user)

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(User.staff_user),
        sponsor: Hydro::EntitySerializer.user(@sponsor),
        sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
        reason: :SPONSOR_INITIATED,
        forced: true,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "sends sponsors.sponsorship_cancel_request with nil actor when argument is nil" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorship.instrument_cancel_request(reason: :SPONSOR_INITIATED, force: true)

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: nil,
        sponsor: Hydro::EntitySerializer.user(@sponsor),
        sponsorable: Hydro::EntitySerializer.user(sponsorship.sponsorable),
        reason: :SPONSOR_INITIATED,
        forced: true,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end
  end

  context "#instrument_payment_complete" do
    test "performs fanout" do
      T.unsafe(GitHub).reset_stratocaster

      user = create(:user)
      user.follow(@sponsor)
      sponsorship = create(:sponsorship, :unpaid, sponsorable: @sponsorable, sponsor: @sponsor)

      refute GitHub.stratocaster_store.last

      perform_enqueued_jobs(only: [ProcessEventJob]) do
        sponsorship.instrument_payment_complete(tier_paid: sponsorship.tier,
          via_bulk_sponsorship: false)
      end

      refute_nil event = GitHub.stratocaster_store.last, "expected to have an event"
    end

    test "triggers a stratocaster event on first payment complete when sponsorship is public" do
      public_sponsorship = create(:sponsorship, :unpaid, sponsorable: @sponsorable, sponsor: @sponsor)

      assert_enqueued_with(job: ProcessEventJob, args: ["SponsorEvent", [@sponsor.id, @sponsorable.id]]) do
        public_sponsorship.instrument_payment_complete(tier_paid: public_sponsorship.tier,
          via_bulk_sponsorship: false)
      end
    end

    test "does not trigger a stratocaster event on subsequent payment complete events" do
      public_sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item,
        sponsorable: @sponsorable,
        sponsor: @sponsor
      )

      assert_no_enqueued_jobs(only: ProcessEventJob) do
        public_sponsorship.instrument_payment_complete(tier_paid: public_sponsorship.tier,
          via_bulk_sponsorship: false)
      end
    end

    test "does not trigger a stratocaster event on create when sponsorship is private" do
      private_sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, sponsor: @sponsor)

      assert_no_enqueued_jobs(only: ProcessEventJob) do
        private_sponsorship.instrument_payment_complete(tier_paid: private_sponsorship.tier,
          via_bulk_sponsorship: false)
      end
    end
  end
end if GitHub.sponsors_enabled?
