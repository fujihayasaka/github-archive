# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::StateDependencyTest < GitHub::TestCase
  include ActionMailer::TestHelper
  include AuditLog::IntegrationTestHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers
  include TradeControls::SdnScreeningTestHelper
  include TradeCompliance::TradeScreening::TradeScreeningTestHelpers

  fixtures do
    @listing = create(:sponsors_listing)
    @approved_listing = create(:sponsors_listing, :approved)
    @disabled_listing = create(:sponsors_listing, :disabled)
    @pending_listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :pending_approval)
    @waitlisted_listing = create(:sponsors_listing, :waitlisted, :with_customized_sponsorable_profile)
    @staff = create(:staff_admin_user, login: GitHub.staff_user_login)
    @auto_approvable_sponsorable = create(:user, :sponsors_auto_approvable)
    @auto_approvable_listing = @auto_approvable_sponsorable.sponsors_listing
    @publishable_sponsorable = create(:user, :sponsors_publishable)
    @publishable_listing = @publishable_sponsorable.sponsors_listing
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    GitHub.flipper[:live_sdn_screening].disable
  end

  context "#accepted_into_sponsors?" do
    test "true for draft listing" do
      listing = build(:sponsors_listing, state: :draft)
      assert_predicate listing, :accepted_into_sponsors?
    end

    test "true for pending_approval listing" do
      listing = build(:sponsors_listing, state: :pending_approval)
      assert_predicate listing, :accepted_into_sponsors?
    end

    test "true for approved listing" do
      listing = build(:sponsors_listing, state: :approved)
      assert_predicate listing, :accepted_into_sponsors?
    end

    test "true for spammy listing" do
      listing = build(:sponsors_listing, state: :spammy)
      assert_predicate listing, :accepted_into_sponsors?
    end

    test "true for SDN disabled listing" do
      listing = build(:sponsors_listing, state: :sdn_disabled)
      assert_predicate listing, :accepted_into_sponsors?
    end

    test "false for waitlisted listing" do
      listing = build(:sponsors_listing, state: :waitlisted)
      refute_predicate listing, :accepted_into_sponsors?
    end

    test "false for banned listing" do
      listing = build(:sponsors_listing, state: :banned)
      refute_predicate listing, :accepted_into_sponsors?
    end

    test "true for disabled listing" do
      assert_predicate @disabled_listing, :accepted_into_sponsors?
    end
  end

  context "#signup_in_progress?" do
    test "true for draft and pending_approval listings" do
      states = [:draft, :pending_approval]

      states.each do |state|
        listing = build(:sponsors_listing, state: state)
        assert_predicate listing, :signup_in_progress?
      end
    end

    test "false for all other listing states" do
      all_states = SponsorsListing.workflow_spec.state_names
      states = all_states - [:draft, :pending_approval]

      states.each do |state|
        listing = build(:sponsors_listing, state: state)
        refute_predicate listing, :signup_in_progress?
      end
    end
  end

  context "state transitions" do
    test "listing is draft by default" do
      listing = create(:sponsors_listing)
      assert_predicate listing, :draft?
    end

    test "listing can transition to draft from waitlisted" do
      assert @waitlisted_listing.accept!

      assert_predicate @waitlisted_listing.reload, :draft?
      refute_nil @waitlisted_listing.accepted_at
    end

    test "accepting a listing defaults to sending an acceptance email" do
      assert_emails 1 do
        assert @waitlisted_listing.accept!
      end

      assert_predicate @waitlisted_listing.reload, :draft?
      refute_nil @waitlisted_listing.accepted_at
    end

    test "accepting a listing respects omitting an acceptance email" do
      assert_emails 0 do
        assert @waitlisted_listing.accept!(send_acceptance_email: false)
      end

      assert_predicate @waitlisted_listing.reload, :draft?
      refute_nil @waitlisted_listing.accepted_at
    end

    test "syncs with Patreon when transitioning to draft state from waitlisted" do
      spu = create(:sponsors_patreon_user, :sponsor, user: @waitlisted_listing.sponsorable)
      @waitlisted_listing.actor = @staff

      # Wait long enough to allow enqueuing the same job for the sponsorable, since creating the SponsorsPatreonUser
      # enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: @staff }]) do
          assert @waitlisted_listing.accept!
        end
      end
    end

    test "listing for org can transition to draft from waitlisted if country supported" do
      org = create(:organization)
      listing = create(:sponsors_listing,
        :waitlisted,
        :with_customized_sponsorable_profile,
        sponsorable: org,
        billing_country: Billing::StripeConnect::Account.supported_countries.first)
      assert_nil listing.accepted_at

      assert listing.accept!

      assert_predicate listing.reload, :draft?
      refute_nil listing.accepted_at
    end

    test "cannot transition to draft if user is trade restricted" do
      ofac_user = create(:verified_user, :fully_trade_restricted)
      ofac_listing = create(:sponsors_listing, :waitlisted, sponsorable: ofac_user)

      refute ofac_listing.accept!
      assert_predicate ofac_listing, :halted?
      assert_equal "Trade-restricted users are not eligible for GitHub Sponsors",
        ofac_listing.halted_because
      refute_predicate ofac_listing.reload, :draft?
    end

    test "cannot transition from waitlisted to draft if not eligible for sponsors" do
      refute_includes Billing::StripeConnect::Account.supported_countries, "IR",
      "expecting Iran not to be a supported country for this test"
      sponsorable = create(:user, time_zone_name: "Tehran",
        created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
      )
      listing = create(:sponsors_listing, sponsorable: sponsorable, full_description: "", short_description: "", state: :waitlisted)

      refute_predicate listing, :eligible_for_sponsors?

      reset_hydro # clear message emitted during listing creation

      # serialize before transition since events will be emitted before state transition
      serialized_sponsorable = Hydro::EntitySerializer.user(listing.sponsorable)
      serialized_listing = Hydro::EntitySerializer.sponsors_listing(listing)
      serialized_stafftools_metadata = Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        listing.stafftools_metadata
      )

      perform_enqueued_jobs(only: BanSponsorsListingJob) { listing.accept! }

      assert_predicate listing, :halted?
      assert_equal SponsorsListing.auto_ban_halt_message, listing.halted_because
      assert_predicate listing.reload, :banned?

      expected_message = {
        user: serialized_sponsorable,
        action: "BANNED",
        listing: serialized_listing,
        listing_stafftools_metadata: serialized_stafftools_metadata,
        automated: true,
      }

      assert_hydro_published(expected_message, schema: "github.sponsors.v0.AccountStatusChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "listing for org cannot transition to draft from waitlisted if country unsupported" do
      listing = create(:sponsors_listing, :waitlisted, :for_org, billing_country: "AQ")
      assert_raises(Workflow::NoTransitionAllowed) { listing.accept! }
      assert_predicate listing, :waitlisted?
    end


    test "does not set payout probation dates on acceptance if subject to payout probation" do
      listing = create(:sponsors_listing, :matchable, :waitlisted, :with_customized_sponsorable_profile)
      assert_nil listing.payout_probation_started_at
      assert_nil listing.payout_probation_ended_at

      listing.actor = @staff
      assert listing.accept!

      assert_nil listing.reload.payout_probation_started_at
      assert_nil listing.payout_probation_ended_at
    end

    test "transitions from approved to spammy" do
      assert_predicate @approved_listing, :can_mark_spammy?
      assert @approved_listing.mark_spammy!
      assert_predicate @approved_listing.reload, :spammy?
    end

    test "cannot transition from draft to spammy" do
      assert_predicate @listing, :draft?
      assert_raises(Workflow::NoTransitionAllowed) do
        @listing.mark_spammy!
      end
    end

    test "cannot transition from waitlisted to spammy" do
      assert_raises(Workflow::NoTransitionAllowed) do
        @waitlisted_listing.mark_spammy!
      end
    end

    test "cannot transition from pending_approval to spammy" do
      assert_raises(Workflow::NoTransitionAllowed) do
        @pending_listing.mark_spammy!
      end
    end

    test "cannot transition from disabled to spammy" do
      assert_raises(Workflow::NoTransitionAllowed) do
        @disabled_listing.mark_spammy!
      end
    end

    test "transitions from spammy to approved" do
      spammy_listing = create(:sponsors_listing, :spammy)
      assert_predicate spammy_listing, :can_mark_not_spammy?
      assert spammy_listing.mark_not_spammy!
      assert_predicate spammy_listing.reload, :approved?
    end

    test "transitions from spammy to banned" do
      spammy_listing = create(:sponsors_listing, :spammy)
      metadata = spammy_listing.stafftools_metadata
      assert_predicate spammy_listing, :can_ban?

      spammy_listing.actor = @staff
      assert spammy_listing.ban!(banned_reason: "reasons")

      assert_predicate spammy_listing.reload, :banned?
      assert_equal @staff.id, metadata.reload.banned_by_id
      assert_equal "reasons", metadata.banned_reason
      refute_nil metadata.banned_at
    end

    test "syncs with Patreon when transitioning to banned state from spammy" do
      spammy_listing = create(:sponsors_listing, :spammy)
      spu = create(:sponsors_patreon_user, :sponsor, user: spammy_listing.sponsorable)
      spammy_listing.actor = @staff

      # Wait long enough to allow enqueuing the same job for the sponsorable, since creating the SponsorsPatreonUser
      # enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_no_enqueued_jobs(only: SyncPatreonSponsorshipsJob) do
        assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: @staff }]) do
          assert spammy_listing.ban!(banned_reason: "reasons")
        end
      end
    end

    test "transitions from draft to pending_approval" do
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)
      listing.update!(full_description: "test hello yes")
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      trade_screening_record = listing.trade_screening_record

      assert_predicate listing.reload, :can_request_approval?,
        "need a listing that can go to pending_approval state"

      listing.request_approval!

      assert_predicate listing.reload, :pending_approval?
      assert_equal "not_screened", trade_screening_record.reload.msft_trade_screening_status
      refute_nil metadata.reload.reviewed_at
    end

    test "does not sync with Patreon when transitioning to pending approval from draft because both states are considered accepted into Sponsors" do
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)
      listing.update!(full_description: "test hello yes")
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      create(:sponsors_patreon_user, user: listing.sponsorable)

      # Wait long enough to allow enqueuing the same job for the sponsorable, since creating the SponsorsPatreonUser
      # enqueues one:
      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_no_enqueued_jobs(only: [SyncSponsorsPatreonUserJob, SyncPatreonSponsorshipsJob]) do
        listing.request_approval!
      end
    end

    test "does not transition from draft to pending_approval if listing is not eligible for sponsors" do
      sponsorable = create(:user, time_zone_name: "Tehran",
        created_at: (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN - 1.day).ago
      )
      listing = create(:sponsors_listing, :ready_for_submission, sponsorable: sponsorable)

      assert_predicate listing, :sponsorable_young_enough_for_auto_ban?,
        "created_at date must be older than ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN"
      refute_predicate listing, :sponsorable_has_customized_user_profile?,
        "need a sponsorable with no customized user profile"
      assert_operator listing.public_contribution_count, :<, 1
      refute_predicate listing, :sponsorable_has_supported_timezone?,
        "need a sponsorable with a non-supported timezone"

      assert_predicate listing.reload, :can_request_approval?,
        "need a listing that can go to pending_approval state"

      perform_enqueued_jobs(only: [BanSponsorsListingJob]) { listing.request_approval! }

      assert_predicate listing, :halted?
      assert_equal SponsorsListing.auto_ban_halt_message, listing.halted_because
      assert_predicate listing.reload, :banned?
    end

    test "transitions from draft to pending_approval with sdn screening enabled will trigger screening" do
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)
      listing.update!(full_description: "test hello yes")
      GitHub.flipper[:live_sdn_screening].enable(listing.sponsorable)

      trade_screening_record = listing.trade_screening_record
      live_response = build_screening_response(screening_profile: trade_screening_record, status: "No Hit")
      TradeCompliance::TradeScreening::ApiService.stubs(:request_trade_screening).returns(live_response)

      assert_predicate listing.reload, :can_request_approval?,
        "need a listing that can go to pending_approval state"

      listing.request_approval!

      assert_predicate listing.reload, :pending_approval?
      assert_equal "no_hit", trade_screening_record.reload.msft_trade_screening_status
    end

    test "transitions from draft to pending_approval when listing's fiscal host has not verified stripe w8 or w9" do
      sponsorable = create(:user, :with_trade_screening_record)
      listing = create(:sponsors_listing, :draft, :with_fiscal_host, :with_customized_sponsorable_profile, sponsorable: sponsorable)
      listing.update!(full_description: "test hello yes")
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      trade_screening_record = listing.trade_screening_record

      assert_predicate listing.reload, :can_request_approval?,
        "need a listing that can go to pending_approval state"

      listing.request_approval!

      assert_predicate listing.reload, :pending_approval?
      assert_equal "not_screened", trade_screening_record.reload.msft_trade_screening_status
      refute_nil metadata.reload.reviewed_at
    end

    test "transitions from waitlisted to pending_approval" do
      listing = create(:sponsors_listing, :waitlisted, :with_customized_sponsorable_profile)
      listing.update!(full_description: "test hello yes")
      create(:sponsors_tier, :published, sponsors_listing: listing)
      create(:stripe_connect_account, sponsors_listing: listing)
      create(:account_screening_profile, owner: listing.sponsorable)
      assert_predicate listing.reload, :can_request_approval?,
        "need a listing that can go to pending_approval state"

      listing.request_approval!

      assert_predicate listing.reload, :pending_approval?
    end

    test "transitions from draft to disabled" do
      listing = create(:sponsors_listing)
      listing.actor = @staff
      listing.disable!
      assert_predicate listing.reload, :disabled?
    end

    test "transitions from pending_approval to approved" do
      listing = create(:sponsors_listing, :with_w8_or_w9_verified_stripe_account, :pending_approval)
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      assert listing.approvable_by?(@staff), "need listing to be approvable"

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: listing.sponsorable_id }],
      ) do
        listing.actor = @staff
        listing.approve!
      end

      assert_predicate listing.reload, :approved?
      refute_nil metadata.reload.reviewed_at
    end

    test "transitions from pending_approval to approved when listing's fiscal host has not verified stripe w8 or w9" do
      sponsorable = create(:user, :with_trade_screening_record)
      listing = create(:sponsors_listing, :draft, :with_fiscal_host, :with_customized_sponsorable_profile, sponsorable: sponsorable)
      listing.update!(full_description: "test hello yes")
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      trade_screening_record = listing.trade_screening_record

      assert_predicate listing.reload, :can_request_approval?,
        "need a listing that can go to pending_approval state"

      listing.request_approval!

      assert_predicate listing.reload, :pending_approval?
      assert_predicate listing, :ready_for_approval?

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: listing.sponsorable_id }],
      ) do
        listing.actor = @staff
        listing.approve!
      end

      assert_predicate listing.reload, :approved?
      refute_nil metadata.reload.reviewed_at
    end

    test "transitions from pending_approval to draft" do
      listing = create(:sponsors_listing, :pending_approval)
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)

      listing.cancel_approval_request!

      assert_predicate listing.reload, :draft?
      refute_nil metadata.reload.reviewed_at
    end

    test "transitions from approved to pending_approval, cancelling active sponsorships and emailing sponsors" do
      listing = create(:sponsors_listing, :approved)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)
      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).once
        .with(sponsorable: listing.sponsorable, sponsor: active_sponsorship.sponsor, tier: active_sponsorship.tier)
        .returns(stub(deliver_later: nil))
      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).never.with(
        sponsorable: listing.sponsorable, sponsor: inactive_sponsorship.sponsor, tier: inactive_sponsorship.tier
      )

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: listing.sponsorable_id }],
      ) do
        perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
          listing.actor = @staff
          listing.unpublish!
        end
      end

      assert_predicate listing.reload, :pending_approval?
      refute_predicate active_sponsorship.reload, :active?
      refute_predicate active_sponsorship.reload_subscription_item, :active?
    end

    test "unpublishing a listing cancels existing invoiced sponsorship subscription item" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @approved_listing.sponsorable)

      assert_equal invoiced_org.sponsors_plan_subscription, sponsorship.plan_subscription

      assert_predicate sponsorship.subscription_item, :active?
      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        @approved_listing.actor = @staff
        @approved_listing.unpublish!
      end
      refute_predicate sponsorship.reload.subscription_item, :active?
    end

    test "unpublishing a listing with active sponsorships instruments Hydro event SponsorshipCancelRequest" do
      listing = create(:sponsors_listing, :approved)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(active_sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(active_sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(active_sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          active_sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(@staff),
        sponsor: Hydro::EntitySerializer.user(active_sponsorship.sponsor),
        sponsorable: Hydro::EntitySerializer.user(active_sponsorship.sponsorable),
        reason: :UNPUBLISHED_LISTING,
        forced: true
      }

      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        listing.actor = @staff
        listing.unpublish!
      end

      assert_predicate listing.reload, :pending_approval?
      refute_predicate active_sponsorship.reload, :active?
      refute_predicate active_sponsorship.reload_subscription_item, :active?

      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "transitions from approved to disabled, cancelling active sponsorships and emailing sponsors" do
      listing = create(:sponsors_listing, :approved)
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)
      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).once
        .with(sponsorable: listing.sponsorable, sponsor: active_sponsorship.sponsor, tier: active_sponsorship.tier)
        .returns(stub(deliver_later: nil))
      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).never.with(
        sponsorable: listing.sponsorable, sponsor: inactive_sponsorship.sponsor, tier: inactive_sponsorship.tier
      )

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: listing.sponsorable_id }],
      ) do
        perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
          listing.actor = @staff
          listing.disable!
        end
      end

      assert_predicate listing.reload, :disabled?
      refute_nil metadata.reload.reviewed_at
      refute_predicate active_sponsorship.reload, :active?
      refute_predicate active_sponsorship.reload_subscription_item, :active?
    end

    test "transitions from approved to sdn_disabled, without cancelling active sponsorships" do
      listing = create(:sponsors_listing, :approved)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)

      GitHub.flipper[:live_sdn_screening].enable(listing.sponsorable)

      assert_predicate listing, :approved?
      assert_predicate listing, :can_sdn_disable?

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: listing.sponsorable_id }],
      ) do
        listing.sdn_disable!
      end

      assert_predicate listing.reload, :sdn_disabled?
      assert_predicate active_sponsorship.reload, :active?
      assert_predicate active_sponsorship.reload_subscription_item, :active?
      refute_predicate inactive_sponsorship.reload, :active?
      refute_predicate inactive_sponsorship.reload_subscription_item, :active?

      status = listing.sponsorable_trade_screening_status
      assert_dogstats_increment(1, "sponsors_listing.sdn_disable", tags: ["status:#{status}"])
    end

    test "transitions from approved to sdn_disabled and disables stripe automated payments" do
      listing = create(:sponsors_listing, :approved, :with_automatic_payout_stripe_account)

      GitHub.flipper[:live_sdn_screening].enable(listing.sponsorable)

      refute_predicate listing.active_stripe_connect_account, :automated_payouts_disabled?

      assert_enqueued_with(
        job: ConfigureStripeAccountJob,
        args: [listing.active_stripe_connect_account, {
          freeze_payouts: true,
          actor: nil,
          reason: SponsorsListing::StateDependency::SDN_DISABLE_REASON,
        }]
      ) do
        listing.sdn_disable!
      end

      assert_predicate listing.reload, :sdn_disabled?

      status = listing.sponsorable_trade_screening_status
      assert_dogstats_increment(1, "sponsors_listing.sdn_disable", tags: ["status:#{status}"])
    end

    test "does not transition from approved to sdn_disabled when live_sdn_screening is disabled" do
      listing = create(:sponsors_listing, :approved)

      assert_predicate listing, :approved?
      refute_predicate listing, :can_sdn_disable?

      assert_raises Workflow::NoTransitionAllowed do
        listing.sdn_disable!
      end

      assert_dogstats_increment(0, "sponsors_listing.sdn_disable")
    end

    test "does not transition from approved when sponsorable is an organization" do
      listing = create(:sponsors_listing, :approved, sponsorable: create(:organization))

      assert_predicate listing, :approved?
      refute_predicate listing, :can_sdn_disable?

      assert_raises Workflow::NoTransitionAllowed do
        listing.sdn_disable!
      end

      assert_dogstats_increment(0, "sponsors_listing.sdn_disable")
    end

    test "transitions from sdn_disabled to approved" do
      listing = create(:sponsors_listing, :sdn_disabled, :with_stripe_account)
      assert_predicate listing.active_stripe_connect_account, :automated_payouts_disabled?

      assert_predicate listing, :sdn_disabled?
      assert_predicate listing, :can_sdn_enable?

      assert_enqueued_with(
        job: ConfigureStripeAccountJob,
        args: [listing.active_stripe_connect_account, {
          freeze_payouts: false,
          actor: nil,
        }]
      ) do
        assert_enqueued_with(
          job: UpdateOwnerRepositorySponsorablesJob,
          args: [{ sponsorable_id: listing.sponsorable_id }],
        ) do
          listing.sdn_enable!
        end
      end

      assert_predicate listing.reload, :approved?

      status = listing.sponsorable_trade_screening_status
      assert_dogstats_increment(1, "sponsors_listing.sdn_enable", tags: ["status:#{status}"])
    end

    test "transitions from approved to draft" do
      listing = create(:sponsors_listing, :approved)

      assert_predicate listing, :approved?
      assert_predicate listing, :can_redraft?

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: listing.sponsorable_id }],
      ) do
        listing.redraft!
      end

      assert_predicate listing.reload, :draft?
    end

    test "transitions from disabled to draft" do
      assert_predicate @disabled_listing, :can_reactivate?
      @disabled_listing.reactivate!
      assert_predicate @disabled_listing.reload, :draft?
    end

    test "does not transition from approved to draft when listing has an active subscription" do
      listing = create(:sponsors_listing, :approved, :with_tier)
      create(:sponsors_subscription_item, subscribable: listing.default_tier, quantity: 1)

      assert_predicate listing, :approved?
      refute_predicate listing, :can_redraft?

      assert_raises Workflow::NoTransitionAllowed do
        listing.redraft!
      end
    end

    test "transitions from approved to draft when listing has an inactive subscription" do
      listing = create(:sponsors_listing, :approved, :with_tier)
      create(:sponsors_subscription_item, subscribable: listing.default_tier, quantity: 0)

      assert_predicate listing, :approved?
      assert_predicate listing, :can_redraft?

      listing.redraft!

      assert_predicate listing.reload, :draft?
    end

    test "disabling a listing cancels existing sponsorship subscription items" do
      listing = create(:sponsors_listing, :approved, :with_tier)
      sponsorships = create_list(:sponsorship, 2, tier: listing.default_tier)
      subscriptions = sponsorships.map(&:subscription_item)

      subscriptions.each do |subscription|
        assert_predicate subscription, :active?
      end
      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        listing.actor = @staff
        listing.disable!
      end
      subscriptions.each do |subscription|
        refute_predicate subscription.reload, :active?
      end
    end

    test "disabling a listing cancels existing invoiced sponsorship subscription item" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @approved_listing.sponsorable)

      assert_equal invoiced_org.sponsors_plan_subscription, sponsorship.plan_subscription

      assert_predicate sponsorship.subscription_item, :active?
      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        @approved_listing.actor = @staff
        @approved_listing.disable!
      end
      refute_predicate sponsorship.reload.subscription_item, :active?
    end

    test "disabling a listing with active sponsorships instruments Hydro event SponsorshipCancelRequest" do
      listing = create(:sponsors_listing, :approved)
      metadata = listing.stafftools_metadata
      metadata.update!(reviewed_at: nil)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(active_sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(active_sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(active_sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          active_sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(@staff),
        sponsor: Hydro::EntitySerializer.user(active_sponsorship.sponsor),
        sponsorable: Hydro::EntitySerializer.user(active_sponsorship.sponsorable),
        reason: :DISABLED_LISTING,
        forced: true
      }

      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        listing.actor = @staff
        listing.disable!
      end

      assert_predicate listing.reload, :disabled?
      refute_nil metadata.reload.reviewed_at
      refute_predicate active_sponsorship.reload, :active?
      refute_predicate active_sponsorship.reload_subscription_item, :active?

      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "transition to queued_for_auto_approval for eligible listing when approval is requested" do
      @auto_approvable_listing.update!(state: :draft)

      assert_predicate @auto_approvable_listing, :auto_approvable?
      @auto_approvable_listing.request_approval!
      assert_predicate @auto_approvable_listing.reload, :queued_for_auto_approval?
    end

    test "enqueues an auto approval job for eligible listing when approval is requested" do
      @auto_approvable_listing.update!(state: :draft)

      assert_predicate @auto_approvable_listing, :auto_approvable?

      assert_enqueued_with(job: AutoApproveSponsorsListingJob) do
        @auto_approvable_listing.request_approval!
      end
    end

    test "does not transition to queued_for_auto_approval for ineligible listing when approval is requested" do
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)

      refute_predicate listing.reload, :auto_approvable?
      listing.request_approval!
      assert_predicate listing, :pending_approval?
    end

    test "does not enqueue an auto approval job for ineligible listing when approval is requested" do
      listing = create(:sponsors_listing, :ready_for_submission,
        sponsorable: create(:organization))

      assert_no_enqueued_jobs(only: AutoApproveSponsorsListingJob) do
        listing.request_approval!
      end
    end

    test "synchronizes search index for sponsorable and their repos on approval" do
      sponsorable = @pending_listing.sponsorable
      sponsorable_guid = AddToSearchIndexJob.guid("user", sponsorable.id)
      repo1 = create(:repository, owner: sponsorable)
      repo2 = create(:private_repository, owner: sponsorable)

      freeze_time do
        assert_enqueued_with(
          job: SyncSponsorsSearchIndicesJob,
          args: [sponsorable: sponsorable]
        ) do
          @pending_listing.approve!
        end
      end
    end

    test "syncs to zuora on approval" do
      assert_enqueued_with(job: SponsorsListingZuoraSyncJob, args: [@pending_listing]) do
        @pending_listing.approve!
      end

      assert_predicate @pending_listing, :approved?
    end

    test "emails sponsorable when approval is requested" do
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)

      SponsorsPrimerMailer.expects(:approval_request_submitted)
                    .once
                    .with(sponsorable: listing.sponsorable)
                    .returns(stub(deliver_later: nil))

      listing.request_approval!
    end

    test "instruments audit log event when listing is redrafted" do
      events = subscribe "sponsors.sponsored_developer_redraft"

      listing = create(:sponsors_listing, :approved)
      listing.redraft!

      expected_payload = {
        user: listing.sponsorable_login,
        user_id: listing.sponsorable.id,
        short_description: listing.short_description,
        sponsors_listing: listing.slug,
        sponsors_listing_id: listing.id,
        state: :approved,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log event when listing is disabled" do
      events = subscribe "sponsors.sponsored_developer_disable"
      actor = create(:user)

      listing = create(:sponsors_listing, :approved)
      listing.actor = actor
      listing.disable!

      expected_payload = {
        user: listing.sponsorable_login,
        user_id: listing.sponsorable.id,
        short_description: listing.short_description,
        sponsors_listing: listing.slug,
        sponsors_listing_id: listing.id,
        state: :approved,
        actor: actor.login,
        actor_id: actor.id,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log event when approval request is cancelled" do
      events = subscribe "sponsors.sponsored_developer_redraft"

      listing = create(:sponsors_listing, :pending_approval)
      listing.cancel_approval_request!

      expected_payload = {
        user: listing.sponsorable_login,
        user_id: listing.sponsorable.id,
        redrafted_because: "approval request canceled",
        short_description: listing.short_description,
        sponsors_listing: listing.slug,
        sponsors_listing_id: listing.id,
        state: :pending_approval,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log event when approval is requested" do
      events = subscribe "sponsors.sponsored_developer_request_approval"

      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)
      listing.request_approval!

      expected_payload = {
        user: listing.sponsorable_login,
        user_id: listing.sponsorable.id,
        short_description: listing.short_description,
        sponsors_listing: listing.slug,
        sponsors_listing_id: listing.id,
        state: :pending_approval,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      }
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro event when approval is requested" do
      listing = create(:sponsors_listing, :ready_for_submission, :with_customized_sponsorable_profile)

      listing.request_approval!

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user: Hydro::EntitySerializer.user(listing.sponsorable),
        action: "REQUESTED_APPROVAL",
      }

      assert_hydro_published(message, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "instruments hydro event when queued for auto approval" do
      @auto_approvable_listing.cancel_approval_request!
      @auto_approvable_listing.reload.request_approval!

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        user: Hydro::EntitySerializer.user(@auto_approvable_listing.sponsorable),
        action: "QUEUED_FOR_AUTO_APPROVAL",
      }

      assert_hydro_published(message, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "instruments audit log when queued for auto approval" do
      @auto_approvable_listing.cancel_approval_request!

      events = assert_performed_audit_entries(
        count: 1,
        only: "sponsors.sponsored_developer_queued_for_auto_approval"
      ) do
        @auto_approvable_listing.reload.request_approval!
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        user: @auto_approvable_listing.sponsorable_login,
        user_id: @auto_approvable_listing.sponsorable.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        short_description: @auto_approvable_listing.short_description,
        sponsors_listing: @auto_approvable_listing.slug,
        sponsors_listing_id: @auto_approvable_listing.id,
        state: :pending_approval,
        created_by: @auto_approvable_listing.sponsorable_login,
        created_by_id: @auto_approvable_listing.sponsorable_id,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "can transition from waitlisted to banned" do
      listing = create(:sponsors_listing, :waitlisted)
      listing.actor = @staff
      listing.ban!(banned_reason: "reasons")
      assert_predicate listing.reload, :banned?
    end

    test "can transition from draft to banned" do
      listing = create(:sponsors_listing)
      assert_predicate listing, :draft?

      listing.actor = @staff
      listing.ban!(banned_reason: "reasons")

      assert_predicate listing.reload, :banned?
    end

    test "can transition from disabled to banned" do
      @disabled_listing.actor = @staff
      @disabled_listing.ban!(banned_reason: "reasons")
      assert_predicate @disabled_listing.reload, :banned?
      assert_equal @staff, @disabled_listing.reload_stafftools_metadata.banned_by
      assert_equal "reasons", @disabled_listing.stafftools_metadata.banned_reason
    end

    test "can transition from queued_for_auto_approval to banned" do
      listing = create(:sponsors_listing, :queued_for_auto_approval)
      listing.actor = @staff
      listing.ban!(banned_reason: "reasons")
      assert_predicate listing.reload, :banned?
    end

    test "banning an approved listing cancels active sponsorships, emails the sponsors, and sets payouts to manual" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)
      one_time_sponsorship = create(:sponsorship, :one_time, sponsorable: listing.sponsorable)
      reason = "reasons"

      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).once
        .with(sponsorable: listing.sponsorable, sponsor: active_sponsorship.sponsor, tier: active_sponsorship.tier)
        .returns(stub(deliver_later: nil))
      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).once
        .with(sponsorable: listing.sponsorable, sponsor: one_time_sponsorship.sponsor, tier: one_time_sponsorship.tier)
        .returns(stub(deliver_later: nil))
      SponsorsPrimerMailer.expects(:sponsorable_no_longer_sponsorable).never.with(
        sponsorable: listing.sponsorable, sponsor: inactive_sponsorship.sponsor, tier: inactive_sponsorship.tier
      )

      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        listing.actor = @staff
        listing.ban!(banned_reason: reason)
      end

      assert_enqueued_jobs 1, only: ConfigureStripeAccountJob, queue: :stripe
      assert_enqueued_with(
        job: ConfigureStripeAccountJob,
        args: [
          listing.active_stripe_connect_account,
          freeze_payouts: true,
          actor: @staff,
          reason: reason,
        ]
      )
      refute_predicate active_sponsorship.reload, :active?
      refute_predicate active_sponsorship.reload_subscription_item, :active?
      refute_predicate one_time_sponsorship.reload_subscription_item, :active?
    end

    test "banning a listing cancels existing invoiced sponsorship subscription item" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @approved_listing.sponsorable)

      assert_equal invoiced_org.sponsors_plan_subscription, sponsorship.plan_subscription

      assert_predicate sponsorship.subscription_item, :active?
      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        @approved_listing.actor = @staff
        @approved_listing.ban!(banned_reason: "reasons")
      end
      refute_predicate sponsorship.reload.subscription_item, :active?
    end

    test "banning a listing with active sponsorships instruments Hydro event SponsorshipCancelRequest" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: listing.sponsorable)
      active_sponsorship = create(:sponsorship, sponsorable: listing.sponsorable)
      one_time_sponsorship = create(:sponsorship, :one_time, sponsorable: listing.sponsorable)
      reason = "reasons"

      expected_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsorship: Hydro::EntitySerializer.sponsorship(active_sponsorship),
        tier: Hydro::EntitySerializer.sponsors_tier(active_sponsorship.tier),
        listing: Hydro::EntitySerializer.sponsors_listing(active_sponsorship.sponsors_listing),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          active_sponsorship.sponsors_listing_stafftools_metadata,
        ),
        actor: Hydro::EntitySerializer.user(@staff),
        sponsor: Hydro::EntitySerializer.user(active_sponsorship.sponsor),
        sponsorable: Hydro::EntitySerializer.user(active_sponsorship.sponsorable),
        reason: :BANNED_LISTING,
        forced: true,
      }

      perform_enqueued_jobs(only: SponsorsListingNoLongerSponsorableJob) do
        listing.actor = @staff
        listing.ban!(banned_reason: reason)
      end

      refute_predicate active_sponsorship.reload, :active?
      refute_predicate active_sponsorship.reload_subscription_item, :active?
      refute_predicate one_time_sponsorship.reload_subscription_item, :active?

      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end

    test "can transition to banned even if listing is in an invalid state" do
      listing = create(:sponsors_listing)
      listing.update_columns(billing_country: "XX")
      refute_predicate listing.reload, :valid?
      assert_predicate listing, :draft?

      assert listing.actor = @staff
      listing.ban!(banned_reason: "reasons")

      assert_predicate listing.reload, :banned?
    end

    test "ban transition records context" do
      listing = create(:sponsors_listing)
      metadata = listing.stafftools_metadata
      now = Time.now
      reason = "Not a good fit for the program at this time"
      listing.actor = @staff

      travel_to(now) { listing.ban!(banned_reason: reason) }

      assert_predicate listing.reload, :banned?
      assert_equal @staff, metadata.reload.banned_by
      assert_equal now.to_i, metadata.banned_at.to_i
      assert_equal reason, metadata.banned_reason
    end

    test "ban transition instruments an audit log and Hydro event" do
      listing = create(:sponsors_listing)

      reset_hydro # clear message emitted during listing creation

      # serialize before transition since events will be emitted before state transition
      serialized_sponsorable = Hydro::EntitySerializer.user(listing.sponsorable)
      serialized_listing = Hydro::EntitySerializer.sponsors_listing(listing)
      serialized_stafftools_metadata = Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        listing.stafftools_metadata
      )

      sponsorable = listing.sponsorable
      reason = "Not a good fit for the program at this time"
      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: sponsorable.login,
        user_id: sponsorable.id,
        banned_reason: reason,
        sponsors_listing_id: listing.id,
        sponsors_listing: listing.slug,
        state: :draft,
        short_description: listing.short_description,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      )
      events = subscribe "sponsors_memberships_ban.create"

      listing.actor = @staff
      listing.ban!(banned_reason: reason)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      expected_message = {
        user: serialized_sponsorable,
        action: "BANNED",
        listing: serialized_listing,
        listing_stafftools_metadata: serialized_stafftools_metadata,
        automated: false,
      }

      assert_hydro_published(expected_message, schema: "github.sponsors.v0.AccountStatusChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "can transition from banned to waitlisted" do
      listing = create(:sponsors_listing, :banned, banned_by: @staff, banned_at: Time.now,
        banned_reason: "reasons")
      metadata = listing.stafftools_metadata
      assert_predicate listing, :banned?

      listing.actor = @staff
      assert listing.un_ban!

      assert_predicate listing.reload, :waitlisted?
      assert_nil metadata.reload.banned_at
      assert_nil metadata.banned_by_id
      assert_nil metadata.banned_reason
    end

    test "un-ban transition instruments an audit log event" do
      listing = create(:sponsors_listing, :banned, banned_by: @staff, banned_at: Time.now,
        banned_reason: "reasons")
      sponsorable = listing.sponsorable
      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge(
        user: sponsorable.login,
        user_id: sponsorable.id,
        sponsors_listing_id: listing.id,
        sponsors_listing: listing.slug,
        short_description: listing.short_description,
        state: :banned,
        created_by: listing.sponsorable_login,
        created_by_id: listing.sponsorable_id,
      )
      events = subscribe "sponsors_memberships_ban.destroy"

      listing.actor = @staff
      listing.un_ban!

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "can transition from draft to approved when feature flag enabled" do

      assert_predicate @publishable_listing, :auto_approvable?

      # serialize before transition since events will be emitted before state transition
      serialized_sponsorable = Hydro::EntitySerializer.user(@publishable_listing.sponsorable)
      serialized_listing = Hydro::EntitySerializer.sponsors_listing(@publishable_listing)
      serialized_stafftools_metadata = Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @publishable_listing.stafftools_metadata
      )

      assert_enqueued_with(
        job: UpdateOwnerRepositorySponsorablesJob,
        args: [{ sponsorable_id: @publishable_listing.sponsorable_id }],
      ) do
        @publishable_listing.publish!
      end

      expected_message = {
        user: serialized_sponsorable,
        action: "APPROVED",
        listing: serialized_listing,
        listing_stafftools_metadata: serialized_stafftools_metadata,
        automated: false,
      }

      assert_predicate @publishable_listing.reload, :approved?
      assert_hydro_published(expected_message, schema: "github.sponsors.v0.AccountStatusChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "does not transition from draft to approved when not auto approvable" do

      refute_predicate @listing.reload, :auto_approvable?

      assert_raises(Workflow::NoTransitionAllowed) { @listing.publish! }

      refute_predicate @listing.reload, :approved?
    end

    test "does not transition from waitlisted to approved when feature flag enabled" do
      @publishable_listing.update(state: :waitlist)

      assert_predicate @publishable_listing.reload, :auto_approvable?

      assert_raises(Workflow::NoTransitionAllowed) { @publishable_listing.publish! }

      refute_predicate @publishable_listing.reload, :approved?
    end
  end

  context "filter_by_state scope" do
    test "filters to listings with given state" do
      assert_predicate @listing, :draft?

      listings = SponsorsListing.filter_by_state("draft")

      assert_includes listings, @listing
      refute_includes listings, @approved_listing
      refute_includes listings, @waitlisted_listing
    end

    test "filters to listings without given state" do
      assert_predicate @listing, :draft?

      listings = SponsorsListing.filter_by_state("not_draft")

      refute_includes listings, @listing
      assert_includes listings, @approved_listing
      assert_includes listings, @waitlisted_listing
    end

    test "does not filter by state when nil is given" do
      assert_predicate @listing, :draft?

      listings = SponsorsListing.filter_by_state(nil)

      assert_includes listings, @listing
      assert_includes listings, @approved_listing
      assert_includes listings, @waitlisted_listing
    end

    test "does not filter by state when 'all' is given" do
      assert_predicate @listing, :draft?

      listings = SponsorsListing.filter_by_state("all")

      assert_includes listings, @listing
      assert_includes listings, @approved_listing
      assert_includes listings, @waitlisted_listing
    end
  end

  context "ordered_by_state scope" do
    test "orders listings by how interesting the state makes them to the user" do
      results = SponsorsListing.where(id: [
        @approved_listing,
        @disabled_listing,
        @pending_listing
      ]).ordered_by_state

      assert_equal [@approved_listing, @pending_listing, @disabled_listing], results
    end
  end

  context "with_states scope" do
    test "returns listings scoped to a specific state" do
      draft_listing = create(:sponsors_listing)
      approved_listing = create(:sponsors_listing, :approved)

      listings = SponsorsListing.with_states(:draft)

      assert_includes listings, draft_listing
      refute_includes listings, approved_listing
    end

    test "returns listings scoped to multiple states" do
      draft_listing = create(:sponsors_listing)
      approved_listing = create(:sponsors_listing, :approved)
      banned_listing = create(:sponsors_listing, :banned)

      listings = SponsorsListing.with_states(:draft, :banned)

      assert_includes listings, draft_listing
      assert_includes listings, banned_listing
      refute_includes listings, approved_listing
    end

    test "also works with strings" do
      draft_listing = create(:sponsors_listing)
      approved_listing = create(:sponsors_listing, :approved)
      banned_listing = create(:sponsors_listing, :banned)

      listings = SponsorsListing.with_states("approved", "banned")

      assert_includes listings, approved_listing
      assert_includes listings, banned_listing
      refute_includes listings, draft_listing
    end

    test "ignores invalid states" do
      assert_empty SponsorsListing.with_states(:nonsense)
    end
  end

  context "without_states scope" do
    test "returns listings that do not have a specific state" do
      draft_listing = create(:sponsors_listing)
      approved_listing = create(:sponsors_listing, :approved)

      listings = SponsorsListing.without_states(:draft)

      refute_includes listings, draft_listing
      assert_includes listings, approved_listing
    end

    test "returns listings that don't have any of the specified states" do
      draft_listing = create(:sponsors_listing)
      approved_listing = create(:sponsors_listing, :approved)
      banned_listing = create(:sponsors_listing, :banned)

      listings = SponsorsListing.without_states(:draft, :banned)

      refute_includes listings, draft_listing
      refute_includes listings, banned_listing
      assert_includes listings, approved_listing
    end

    test "also works with strings" do
      draft_listing = create(:sponsors_listing)
      approved_listing = create(:sponsors_listing, :approved)
      banned_listing = create(:sponsors_listing, :banned)

      listings = SponsorsListing.without_states("approved", "banned")

      refute_includes listings, approved_listing
      refute_includes listings, banned_listing
      assert_includes listings, draft_listing
    end

    test "includes all listings when invalid states are given" do
      assert_same_elements SponsorsListing.all, SponsorsListing.without_states(:nonsense)
    end
  end

  context "#current_state_name" do
    test "returns draft for state 0" do
      listing = SponsorsListing.new(state: :draft)
      assert_equal 0, listing.state
      assert_equal :draft, listing.current_state_name
    end

    test "returns pending_approval for state 4" do
      listing = SponsorsListing.new(state: :pending_approval)
      assert_equal 4, listing.state
      assert_equal :pending_approval, listing.current_state_name
    end

    test "returns requires_additional_review for state 5" do
      listing = SponsorsListing.new(state: :requires_additional_review)
      assert_equal 5, listing.state
      assert_equal :requires_additional_review, listing.current_state_name
    end

    test "returns approved for state 6" do
      listing = SponsorsListing.new(state: :approved)
      assert_equal 6, listing.state
      assert_equal :approved, listing.current_state_name
    end

    test "returns disabled for state 7" do
      listing = SponsorsListing.new(state: :disabled)
      assert_equal 7, listing.state
      assert_equal :disabled, listing.current_state_name
    end

    test "returns queued_for_auto_approval for state 9" do
      listing = SponsorsListing.new(state: :queued_for_auto_approval)
      assert_equal 9, listing.state
      assert_equal :queued_for_auto_approval, listing.current_state_name
    end
  end

  context "#waiting_to_be_reviewed?" do
    test "returns true when listing is in pending_approval" do
      listing = SponsorsListing.new(state: :pending_approval)
      assert_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns true when listing is in requires_additional_review" do
      listing = SponsorsListing.new(state: :requires_additional_review)
      assert_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns true when listing is in waitlisted" do
      listing = SponsorsListing.new(state: :waitlisted)
      assert_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns true when listing is in queued_for_auto_approval" do
      listing = SponsorsListing.new(state: :queued_for_auto_approval)
      assert_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns false when listing is in draft" do
      listing = SponsorsListing.new(state: :draft)
      refute_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns false when listing is in banned" do
      listing = SponsorsListing.new(state: :banned)
      refute_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns false when listing is in approved" do
      listing = SponsorsListing.new(state: :approved)
      refute_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns false when listing is in disabled" do
      listing = SponsorsListing.new(state: :disabled)
      refute_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns false when listing is in sdn_disabled" do
      listing = SponsorsListing.new(state: :sdn_disabled)
      refute_predicate listing, :waiting_to_be_reviewed?
    end

    test "returns false when listing is in spammy" do
      listing = SponsorsListing.new(state: :spammy)
      refute_predicate listing, :waiting_to_be_reviewed?
    end
  end
end
