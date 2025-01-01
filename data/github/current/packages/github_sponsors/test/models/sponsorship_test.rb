# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @sponsorable = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @listing = create(:sponsors_listing, :approved, :with_stripe_account,
      sponsorable: @sponsorable
    )
    @recurring_tier = @listing.default_tier
    @one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @listing)
    @tier_with_repo = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
    @sponsor = create(:credit_card_user, :sponsorable,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons,
    )
    @spammy_user = if GitHub.spamminess_check_enabled?
      create(:credit_card_user, :sponsorable, spammy: true,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons)
    end
    @spammy_org = if GitHub.spamminess_check_enabled?
      create(:credit_card_org, :sponsorable, spammy: true,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons)
    end
    @staff = create(:staff_admin_user)
    @rando = create(:user)

    @basic_sponsorship = create(:sponsorship)
  end

  context "#can_retry_collecting_payment?" do
    test "returns true for one-time, active, unpaid sponsorship with a stale subscription item" do
      sponsorship = create(:sponsorship, :unpaid, tier: @one_time_tier)
      sponsorship.subscription_item.update!(updated_at: 1.day.ago)
      assert_predicate sponsorship, :can_retry_collecting_payment?
    end

    test "returns false for a paid sponsorship" do
      sponsorship = create(:sponsorship, tier: @one_time_tier)
      sponsorship.subscription_item.update!(updated_at: 1.day.ago)
      refute_predicate sponsorship.reload, :can_retry_collecting_payment?
    end

    test "returns false for recurring sponsorship" do
      sponsorship = create(:sponsorship, :unpaid, tier: @recurring_tier)
      sponsorship.subscription_item.update!(updated_at: 1.day.ago)
      refute_predicate sponsorship, :can_retry_collecting_payment?
    end

    test "returns false for inactive sponsorship" do
      sponsorship = create(:sponsorship, :inactive, :unpaid, tier: @one_time_tier)
      sponsorship.subscription_item.update!(updated_at: 1.day.ago)
      refute_predicate sponsorship, :can_retry_collecting_payment?
    end

    test "returns false for a sponsorship without a subscription item" do
      sponsorship = create(:sponsorship, :unpaid, tier: @one_time_tier)
      sponsorship.subscription_item.delete
      refute_predicate sponsorship.reload, :can_retry_collecting_payment?
    end
  end

  context "#via_bulk_sponsorship?" do
    test "returns true for sponsorship created as part of a bulk sponsorship operation" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      create(:sponsors_activity, :new_sponsorship, :via_bulk_sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, sponsors_tier: sponsorship.tier)

      assert_predicate sponsorship, :via_bulk_sponsorship?
    end

    test "returns false for sponsorship not created as part of a bulk sponsorship operation" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      create(:sponsors_activity, :new_sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        sponsors_tier: sponsorship.tier)

      refute_predicate sponsorship, :via_bulk_sponsorship?
    end

    test "can be batch loaded efficiently" do
      sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      create(:sponsors_activity, :new_sponsorship, :via_bulk_sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, sponsors_tier: sponsorship1.tier)

      sponsorship2 = @basic_sponsorship
      create(:sponsors_activity, :new_sponsorship, sponsor: sponsorship2.sponsor,
        sponsorable: sponsorship2.sponsorable, sponsors_tier: sponsorship2.tier)

      sponsorship3 = travel_to(1.month.ago) { create(:sponsorship) }
      travel_to(1.month.ago) do
        create(:sponsors_activity, :new_sponsorship, sponsor: sponsorship3.sponsor,
          sponsorable: sponsorship3.sponsorable, sponsors_tier: sponsorship3.tier)
      end
      create(:sponsors_activity, :new_sponsorship, :via_bulk_sponsorship, sponsor: sponsorship3.sponsor,
        sponsorable: sponsorship3.sponsorable, sponsors_tier: sponsorship3.tier)

      sponsorships = [sponsorship1, sponsorship2, sponsorship3]

      assert_query_count_per_table({ sponsors_activities: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :via_bulk_sponsorship?)
      end

      assert_query_count_per_table({ sponsors_activities: 0 }) do
        assert_predicate sponsorship1, :via_bulk_sponsorship?
        refute_predicate sponsorship2, :via_bulk_sponsorship?
        assert_predicate sponsorship3, :via_bulk_sponsorship?
      end
    end
  end

  context "#async_is_sponsor_opted_into_email_for" do
    test "non-nil when viewer is sponsor" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      result = sponsorship.async_is_sponsor_opted_into_email_for(@sponsor).sync

      refute_nil result
      assert_equal sponsorship.is_sponsor_opted_in_to_email?, result
    end

    test "non-nil when viewer is sponsorable" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      result = sponsorship.async_is_sponsor_opted_into_email_for(@sponsorable).sync

      refute_nil result
      assert_equal sponsorship.is_sponsor_opted_in_to_email?, result
    end

    test "non-nil when viewer is admin of org sponsorable" do
      sponsorship = create(:sponsorship, :with_org_sponsorable, sponsor: @sponsor)
      org = sponsorship.sponsorable

      result = sponsorship.async_is_sponsor_opted_into_email_for(org.admins.first).sync

      refute_nil result
      assert_equal sponsorship.is_sponsor_opted_in_to_email?, result
    end

    test "nil when viewer is billing manager of org sponsorable" do
      sponsorship = create(:sponsorship, :with_org_sponsorable, sponsor: @sponsor)
      org = sponsorship.sponsorable
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      assert_nil sponsorship.async_is_sponsor_opted_into_email_for(billing_manager).sync
    end

    test "nil when viewer is member of org sponsorable" do
      sponsorship = create(:sponsorship, :with_org_sponsorable, sponsor: @sponsor)
      org = sponsorship.sponsorable
      org_member = create(:user)
      org.add_member(org_member)

      assert_nil sponsorship.async_is_sponsor_opted_into_email_for(org_member).sync
    end

    test "non-nil when viewer is admin of org sponsor" do
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      org = sponsorship.sponsor

      result = sponsorship.async_is_sponsor_opted_into_email_for(org.admins.first).sync

      refute_nil result
      assert_equal sponsorship.is_sponsor_opted_in_to_email?, result
    end

    test "non-nil when viewer is billing manager of org sponsor" do
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      org = sponsorship.sponsor
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      result = sponsorship.async_is_sponsor_opted_into_email_for(billing_manager).sync

      refute_nil result
      assert_equal sponsorship.is_sponsor_opted_in_to_email?, result
    end

    test "nil when viewer is member of org sponsor" do
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      assert_nil sponsorship.async_is_sponsor_opted_into_email_for(org_member).sync
    end

    test "nil when viewer is not related to the sponsorship" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_nil sponsorship.async_is_sponsor_opted_into_email_for(@rando).sync
    end

    test "nil when viewer is anonymous" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_nil sponsorship.async_is_sponsor_opted_into_email_for(nil).sync
    end
  end

  context "#pending_subscription_item_change" do
    test "is preloadable" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
        pending_plan_change: create(:billing_pending_plan_change, :active, user: @sponsor),
        subscribable: @recurring_tier)

      sponsorships = Sponsorship.where(id: sponsorship)
      query_counts = {
        sponsorships: 1,
        subscription_item: 0,
        pending_plan_change: 0,
        pending_subscription_item_change: 0
      }

      assert_query_count_per_table(query_counts) do
        GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :pending_subscription_item_change)
      end

      assert_query_count(0) do
        assert_equal pending_sub_item_change, T.must(sponsorships.first).pending_subscription_item_change
      end
    end

    test "returns a pending subscription item change for the sponsorship" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
        pending_plan_change: create(:billing_pending_plan_change, :active, user: @sponsor),
        subscribable: @recurring_tier)

      assert_equal pending_sub_item_change, sponsorship.pending_subscription_item_change
    end

    test "returns a pending subscription item change for an enterprise account member org" do
      sub_item = create(:sponsors_subscription_item, :self_serve_business, subscribable: @recurring_tier)
      business = sub_item.account

      pending_plan_change = create(:billing_pending_plan_change, :business,
        customer: business.customer
      )
      pending_sub_item_change = create(:sponsors_pending_subscription_item_change,
        pending_plan_change: pending_plan_change,
        subscribable: @recurring_tier,
        organization: sub_item.organization,
        quantity: 0
      )

      sponsorship = create(:sponsorship,
        sponsor: sub_item.organization,
        sponsorable: @sponsorable,
        tier: @recurring_tier,
        subscription_item: sub_item
      )

      other_member_org = create(:organization, business: business)
      other_member_org_sub_item = create(:sponsors_subscription_item,
        account: other_member_org,
        subscribable: @recurring_tier
      )
      other_member_org_sponsorship = create(:sponsorship,
        sponsor: other_member_org,
        sponsorable: @sponsorable,
        tier: @recurring_tier,
        subscription_item: other_member_org_sub_item
      )

      assert_equal pending_sub_item_change, sponsorship.pending_subscription_item_change
      assert_nil other_member_org_sponsorship.pending_subscription_item_change
    end

    test "does not return a completed change" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
        pending_plan_change: create(:billing_pending_plan_change, :inactive, user: @sponsor),
        subscribable: @tier_with_repo)

      assert_nil sponsorship.pending_subscription_item_change
    end

    test "does not return a Billing::PendingSubscriptionItemChange for a different tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)
      pending_sub_item_change = create(:billing_pending_subscription_item_change, :cancellation,
        pending_plan_change: create(:billing_pending_plan_change, :inactive, user: @sponsor),
        subscribable: @recurring_tier)

      assert_nil sponsorship.pending_subscription_item_change
    end
  end

  context "#pending_change" do
    test "can be efficiently loaded in bulk for many sponsorships at once" do
      low_tier, high_tier = create_pair(:sponsors_tier, :published, sponsors_listing: @listing)
      sponsorship1 = create(:sponsorship, tier: high_tier)
      sponsorship2 = create(:sponsorship, tier: low_tier)
      sponsorship3 = create(:sponsorship, tier: low_tier)
      pending_sub_item_change1 = create(:billing_pending_subscription_item_change,
        account: sponsorship1.sponsor,
        subscribable: low_tier,
        quantity: 1,
      )
      # no pending change for sponsorship2 so we can ensure nil pending change is returned
      pending_sub_item_change3 = create(:billing_pending_subscription_item_change,
        account: sponsorship3.sponsor,
        subscribable: low_tier,
        quantity: 0,
      )

      sponsorships = Sponsorship.where(id: [sponsorship1, sponsorship2, sponsorship3]).to_a
      query_counts = {
        sponsors_tiers: 2,
        subscription_items: 1,
        pending_plan_changes: 1,
        pending_subscription_item_changes: 1,
        plan_subscriptions: 1,
        users: 1,
      }

      assert_query_count_per_table(query_counts) do
        GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :pending_change)
      end

      assert_query_count(0) do
        assert_equal Sponsorship::PendingChange::Type::Downgrade, T.must(sponsorships.first).pending_change.type
        assert_nil sponsorships.second.pending_change
        assert_equal Sponsorship::PendingChange::Type::Cancellation, sponsorships.third.pending_change.type
      end
    end

    test "returns the sponsorship's pending change" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)
      pending_sub_item_change = create(:billing_pending_subscription_item_change,
        account: @sponsor,
        subscribable: @recurring_tier,
        quantity: 0,
      )

      result = sponsorship.pending_change

      refute_nil result
      assert_equal Sponsorship::PendingChange::Type::Cancellation, result.type
    end
  end

  context "sponsorship_repository relation" do
    test "returns the SponsorshipRepository for the sponsor at the sponsorship's specific tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @recurring_tier)
      assert_nil sponsorship.sponsorship_repository

      sponsorship_repo = create(:sponsorship_repository, sponsor: @sponsor, sponsors_tier: @recurring_tier,
        sponsorable: @sponsorable)
      assert_equal sponsorship_repo, sponsorship.reload_sponsorship_repository
    end
  end

  context ".reject_blocked_sponsorships" do
    test "rejects blocked sponsorship if current user is not the sponsor or sponsorable" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: @rando)

      assert_empty sponsorships
    end

    test "rejects blocked sponsorship if current user is logged out" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: nil)

      assert_empty sponsorships
    end

    test "rejects blocked sponsorship if sponsorable blocks the sponsor, and sponsorable is the current user" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsorable.block(@sponsor)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: @sponsorable)

      assert_empty sponsorships
    end

    test "rejects sponsorship if current user is the sponsor and has blocked the sponsorable" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: @sponsor)

      assert_empty sponsorships
    end

    test "keeps sponsorship if sponsor blocked the sponsorable and sponsorable is the current user" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: @sponsorable)

      assert_equal [sponsorship], sponsorships
    end

    test "keeps sponsorship if sponsorable blocked the sponsor and sponsor is the current user" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsorable.block(@sponsor)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: @sponsor)

      assert_equal [sponsorship], sponsorships
    end

    test "keeps sponsorship if it is not blocked" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorships = Sponsorship.reject_blocked_sponsorships([sponsorship], current_user: @sponsor)

      assert_equal [sponsorship], sponsorships
    end

    test "copies the array and modifies it in place so that it works with WillPaginate ActiveRecord collections" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      sponsorships = Sponsorship.reject_blocked_sponsorships(
        Sponsorship.where(id: [sponsorship.id]).paginate(per_page: 1, page: 1),
        current_user: @sponsor
      )

      assert_equal [sponsorship], sponsorships
      assert_respond_to sponsorships, :total_entries, "Should still be a WillPaginate collection"
      assert_equal 1, T.unsafe(sponsorships).total_entries
    end

    test "prefills the 'blocked' checks so that the method doesn't perform N+1 queries" do
      # Create a pair so that if we forget to prefill something the query count will go up
      sponsorships = create_pair(:sponsorship, sponsorable: @sponsorable)

      assert_query_count(1) do
        Sponsorship.reject_blocked_sponsorships(sponsorships, current_user: @sponsor)
      end
    end
  end

  context ".fee_at_sponsorship_payment_time_for" do
    test "is zero for users" do
      flat_price = Billing::Money.new(100)
      assert_equal Billing::Money.zero, Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: @sponsor, flat_price: flat_price)
    end

    test "is zero for invoiced orgs" do
      invoiced_org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)

      flat_price = Billing::Money.new(100)
      assert_equal Billing::Money.zero, Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: invoiced_org, flat_price: flat_price)
    end

    test "is 6% of flat price for credit card-using orgs" do
      cc_org = create(:credit_card_org)

      flat_price = Billing::Money.new(100)
      assert_equal Billing::Money.new(6), Sponsorship.fee_at_sponsorship_payment_time_for(sponsor: cc_org, flat_price: flat_price)
    end
  end

  context ".sponsor_ids_from" do
    test "includes ID of user sponsor" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      sponsorships = Sponsorship.where(id: sponsorship)

      assert_equal [@sponsor.id], Sponsorship.sponsor_ids_from(sponsorships)
    end

    test "includes ID of organization sponsor" do
      org_sponsor = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      sponsorship = create(:sponsorship, sponsor: org_sponsor, sponsorable: @sponsorable)
      sponsorships = Sponsorship.where(id: sponsorship)

      assert_equal [org_sponsor.id], Sponsorship.sponsor_ids_from(sponsorships)
    end

    test "includes ID of linked organization sponsor" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      sponsorship = create(:sponsorship, sponsor: org_that_pays, sponsorable: @sponsorable)
      sponsorships = Sponsorship.where(id: sponsorship)

      assert_equal [org_that_gets_credit.id], Sponsorship.sponsor_ids_from(sponsorships)
    end
  end

  context ".paid scope" do
    test "includes only paid sponsorships" do
      paid_sponsorship = create(:sponsorship, :paid)
      unpaid_sponsorship = create(:sponsorship, paid_at: nil)

      result = Sponsorship.paid

      assert_includes result, paid_sponsorship
      refute_includes result, unpaid_sponsorship
      assert result.all?(&:paid?), "all returned sponsorships should be paid"
    end
  end

  context ".unpaid scope" do
    test "includes only unpaid sponsorships" do
      paid_sponsorship = create(:sponsorship, :paid)
      unpaid_sponsorship = create(:sponsorship, paid_at: nil)

      result = Sponsorship.unpaid

      refute_includes result, paid_sponsorship
      assert_includes result, unpaid_sponsorship
      assert result.none?(&:paid?), "all returned sponsorships should be unpaid"
    end
  end

  context ".paid_or_patreon scope" do
    test "includes paid or patreon sponsorships only" do
      paid_sponsorship = create(:sponsorship, :paid)
      unpaid_sponsorship = create(:sponsorship, :unpaid)
      patreon_sponsorship = create(:sponsorship, :patreon)

      result = Sponsorship.paid_or_patreon

      assert_includes result, paid_sponsorship
      assert_includes result, patreon_sponsorship
      refute_includes result, unpaid_sponsorship
    end
  end

  context ".active_or_paid scope" do
    test "includes paid or active sponsorships only" do
      paid_sponsorship = create(:sponsorship, :paid)
      unpaid_active_sponsorship = create(:sponsorship, :unpaid)
      patreon_sponsorship = create(:sponsorship, :patreon)
      paid_inactive_sponsorship = create(:sponsorship, :inactive, :paid)
      unpaid_inactive_sponsorship = create(:sponsorship, :inactive, :unpaid)

      result = Sponsorship.active_or_paid

      assert_includes result, paid_sponsorship
      assert_includes result, patreon_sponsorship
      assert_includes result, unpaid_active_sponsorship
      assert_includes result, paid_inactive_sponsorship
      refute_includes result, unpaid_inactive_sponsorship
    end
  end

  context "processing scope" do
    test "includes only unpaid sponsorships that have not expired and have state=pending" do
      expired_unpaid_sponsorship = create(:sponsorship, :expired, :unpaid)
      pending_sponsorship = create(:sponsorship, :pending)

      result = Sponsorship.processing

      refute_includes result, @basic_sponsorship
      refute_includes result, expired_unpaid_sponsorship
      assert_includes result, pending_sponsorship
    end
  end

  context "active_test scope" do
    test "includes only paid sponsorships that have not expired and have active=true" do
      unpaid_sponsorship = create(:sponsorship, :unpaid)
      expired_sponsorship = create(:sponsorship, :expired)

      result = Sponsorship.active_test

      refute_includes result, unpaid_sponsorship
      refute_includes result, expired_sponsorship
      assert_includes result, @basic_sponsorship
    end
  end

  context "inactive_test scope" do
    test "includes only expired sponsorships or those that have active=false" do
      inactive_sponsorship = create(:sponsorship, :inactive)
      expired_sponsorship = create(:sponsorship, :expired)

      result = Sponsorship.inactive_test

      refute_includes result, @basic_sponsorship
      assert_includes result, inactive_sponsorship
      assert_includes result, expired_sponsorship
    end
  end

  context "#cancel" do
    test "emits a Hydro event when cancellation is forced" do
      sponsorship = create(:sponsorship, sponsorable: @listing.sponsorable)
      reset_hydro

      result = sponsorship.cancel(actor: sponsorship.sponsor, force: true)

      assert result.success
      message = {
        actor: Hydro::EntitySerializer.user(sponsorship.sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        matchable: false,
        action: :CANCEL,
        first_time_sponsor: false,
        first_time_sponsorable: false,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "emits a Hydro event when the sponsorship is one-time" do
      sponsorship = create(:sponsorship, :one_time, sponsorable: @listing.sponsorable)
      reset_hydro

      result = sponsorship.cancel(actor: sponsorship.sponsor)

      assert result.success
      message = {
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipExpire")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipExpire")
    end

    test "cancelling a non-Zuora-based invoiced sponsorship marks the sponsorship as inactive and expired" do
      travel_to("2023-03-08") do
        invoiced_org = create(:invoiced_organization)
        transfer = create(:invoiced_sponsorship_transfer, :completed, sponsor: invoiced_org)
        sponsorship = transfer.sponsorship
        reset_hydro

        result = sponsorship.cancel(actor: @staff)

        assert result.success
        refute_predicate sponsorship.reload, :active?
        assert_equal Time.now, sponsorship.expires_at
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      end
    end

    test "cancelling a non-invoiced sponsorship schedules a cancellation by default" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      refute_predicate sponsorship.tier, :has_repository?
      refute_predicate sponsorship, :has_pending_cancellation?

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        assert_difference(-> { Billing::PendingSubscriptionItemChange.count }) do
          result = sponsorship.cancel(actor: @sponsor)
          assert result.success
        end
      end

      assert_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :cancelled?
      assert_predicate sponsorship, :has_pending_cancellation?
    end

    test "cancelling a Zuora-based invoiced sponsorship schedules a cancellation by default" do
      stub_credit_balance do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @sponsorable)
        assert_predicate sponsorship, :sponsors_invoiced?
        refute_predicate sponsorship, :has_pending_cancellation?

        assert_difference(-> { Billing::PendingSubscriptionItemChange.count }) do
          result = sponsorship.cancel(actor: invoiced_org.admin)
          assert result.success
        end

        pending_item_change = Billing::PendingSubscriptionItemChange.last
        refute_nil pending_item_change
        assert_equal 0, T.must(pending_item_change).quantity
        assert_equal invoiced_org.sponsors_plan_subscription, T.must(pending_item_change).plan_subscription
        assert_equal sponsorship.tier, T.must(pending_item_change).subscribable

        pending_plan_change = T.must(pending_item_change).pending_plan_change
        refute_nil pending_plan_change
        assert_equal invoiced_org, T.must(pending_plan_change).user
        assert_equal invoiced_org.admin, T.must(pending_plan_change).actor

        assert_predicate sponsorship.reload, :active?
        refute_predicate sponsorship.reload_subscription_item, :cancelled?
        assert_predicate sponsorship, :has_pending_cancellation?
      end
    end

    test "cancelling a self-serve enterprise member org sponsorship schedules a cancellation by default" do
      freeze_time

      sub_item = create(:sponsors_subscription_item, :self_serve_business)
      business = sub_item.account
      business.update_billing_date(next_billing_date: GitHub::Billing.today, billing_attempts: 0)
      tier = sub_item.subscribable
      listing = sub_item.listing
      sponsorable = listing.sponsorable
      sponsorship = create(:sponsorship, :paid,
        sponsor: sub_item.organization,
        sponsorable: sponsorable,
        tier: tier,
        subscription_item: sub_item
      )

      other_member_org = create(:organization, business: business)
      other_member_org_sub_item = create(:sponsors_subscription_item,
        account: other_member_org,
        subscribable: tier
      )
      other_member_org_sponsorship = create(:sponsorship, :paid,
        sponsor: other_member_org,
        sponsorable: sponsorable,
        tier: tier,
        subscription_item: other_member_org_sub_item
      )

      assert_predicate sponsorship, :active?
      assert_predicate other_member_org_sponsorship, :active?
      refute_predicate sponsorship, :has_pending_cancellation?
      refute_predicate other_member_org_sponsorship, :has_pending_cancellation?

      # using the same plan and subscribable to ensure we differentiate the orgs when cancelling
      assert_equal sub_item.plan_subscription, other_member_org_sub_item.plan_subscription
      assert_equal sub_item.subscribable, other_member_org_sub_item.subscribable

      assert_difference(-> { Billing::PendingSubscriptionItemChange.count }) do
        result = sponsorship.cancel(actor: sub_item.organization.admin)
        assert result.success
      end

      assert_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :cancelled?
      assert_predicate sponsorship, :has_pending_cancellation?

      assert_predicate other_member_org_sponsorship.reload, :active?
      assert_predicate other_member_org_sponsorship.reload_subscription_item, :active?
      refute_predicate other_member_org_sponsorship, :has_pending_cancellation?
    end

    test "enqueues job to sync Patreon user when both sponsor and sponsorable have Patreon set up when recurring sponsorship is force cancelled" do
      create(:sponsors_patreon_user, :sponsor, user: @sponsor)
      sponsorable_patreon_user = create(:sponsors_patreon_user, :with_tier, user: @sponsorable) # enqueues a sync job
      assert_predicate @sponsorable, :sponsorable_via_patreon?, "need the maintainer to allow Patreon"
      sponsorship = create(:sponsorship, :patreon, sponsor: @sponsor, sponsorable: @sponsorable)

      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(
        job: SyncSponsorsPatreonUserJob,
        args: [sponsorable_patreon_user, { actor: @sponsor }],
      ) do
        assert_enqueued_with(
          job: SyncPatreonSponsorshipsJob,
          args: [sponsorable_patreon_user, { actor: @sponsor }],
        ) do
          result = sponsorship.cancel(actor: @sponsor, force: true)
          assert result.success
        end
      end

      refute_predicate sponsorship.reload, :active?
    end

    test "enqueues job to sync Patreon user when sponsorable has Patreon set up and a Patreon sponsorship is cancelled" do
      sponsor_patreon_user = create(:sponsors_patreon_user, :sponsor, user: @sponsor)
      sponsorable_patreon_user = create(:sponsors_patreon_user, :with_tier, user: @sponsorable) # enqueues a sync job

      assert_predicate @sponsorable, :sponsorable_via_patreon?, "need the maintainer to allow Patreon"
      sponsorship = create(:sponsorship, :patreon, sponsor: @sponsor, sponsorable: @sponsorable)
      sponsor_patreon_user.delete
      assert_nil @sponsor.reload.sponsors_patreon_user, "need sponsor to no longer be connected to Patreon"

      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(
        job: SyncSponsorsPatreonUserJob,
        args: [sponsorable_patreon_user, { actor: @sponsor }],
      ) do
        assert_enqueued_with(
          job: SyncPatreonSponsorshipsJob,
          args: [sponsorable_patreon_user, { actor: @sponsor }],
        ) do
          result = sponsorship.cancel(actor: @sponsor, force: true)
          assert result.success
        end
      end

      refute_predicate sponsorship.reload, :active?
    end

    test "enqueues job to sync Patreon user when both sponsor and sponsorable have Patreon set up when one-time sponsorship is force cancelled" do
      create(:sponsors_patreon_user, :sponsor, user: @sponsor)
      sponsorable_patreon_user = create(:sponsors_patreon_user, :with_tier, user: @sponsorable) # enqueues a sync job
      assert_predicate @sponsorable, :sponsorable_via_patreon?, "need the maintainer to allow Patreon"
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @one_time_tier)

      travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

      assert_enqueued_with(
        job: SyncSponsorsPatreonUserJob,
        args: [sponsorable_patreon_user, { actor: @sponsor }],
      ) do
        assert_enqueued_with(
          job: SyncPatreonSponsorshipsJob,
          args: [sponsorable_patreon_user, { actor: @sponsor }],
        ) do
          result = sponsorship.cancel(actor: @sponsor, force: true)
          assert result.success
        end
      end

      refute_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :active?
    end

    test "does not enqueue job to sync Patreon user when sponsor doesn't have Patreon set up" do
      @sponsorable.sponsors_patreon_user = create(:sponsors_patreon_user)
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      assert_no_enqueued_jobs only: [SyncSponsorsPatreonUserJob, SyncPatreonSponsorshipsJob] do
        result = sponsorship.cancel(actor: @sponsor, force: true)
        assert result.success
      end

      refute_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :cancelled?
    end

    test "does not enqueue job to sync Patreon user when sponsorable doesn't have Patreon set up" do
      @sponsor.sponsors_patreon_user = create(:sponsors_patreon_user)
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      assert_no_enqueued_jobs only: [SyncSponsorsPatreonUserJob, SyncPatreonSponsorshipsJob] do
        result = sponsorship.cancel(actor: @sponsor, force: true)
        assert result.success
      end

      refute_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :cancelled?
    end

    test "enqueues job to revoke the sponsor's repo access when cancellation is forced" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @tier_with_repo)
      sponsorship_repo = create(:sponsorship_repository, sponsor: @sponsor, sponsors_tier: @tier_with_repo,
        repository: @tier_with_repo.repository, sponsorable: @sponsorable)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [@sponsor.id, @tier_with_repo.repository_id, @tier_with_repo.id],
      ) do
        result = sponsorship.cancel(actor: @sponsor, force: true)
        assert result.success
      end

      refute_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :cancelled?
    end

    test "enqueues job to revoke the sponsor's repo access granted by the custom tier's parent tier when cancellation is forced" do
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @listing, parent_tier: @tier_with_repo,
        monthly_price_in_cents: @tier_with_repo.monthly_price_in_cents + 1_00)
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: custom_tier)
      sponsorship_repo = create(:sponsorship_repository, sponsor: @sponsor, sponsors_tier: custom_tier,
        repository_id: @tier_with_repo.repository_id, sponsorable: @sponsorable)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [@sponsor.id, @tier_with_repo.repository_id, custom_tier.id],
      ) do
        result = sponsorship.cancel(actor: @sponsor, force: true)
        assert result.success
      end

      refute_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :cancelled?
    end

    test "non-invoiced sponsorship can be cancelled immediately" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      assert_no_difference(-> { Billing::PendingSubscriptionItemChange.count }) do
        result = sponsorship.cancel(actor: @sponsor, force: true)
        assert result.success
      end

      refute_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :cancelled?
    end

    test "Zuora-based invoiced sponsorship can be cancelled immediately" do
      stub_credit_balance do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @sponsorable)
        assert_predicate sponsorship, :sponsors_invoiced?

        assert_no_difference(-> { Billing::PendingSubscriptionItemChange.count }) do
          result = sponsorship.cancel(actor: invoiced_org.admin, force: true)
          assert result.success
        end

        refute_predicate sponsorship.reload, :active?
        assert_predicate sponsorship.reload_subscription_item, :cancelled?
      end
    end

    test "Zuora invoiced sponsorship emits Hydro event when cancelled" do
      travel_to "2023-11-14"
      stub_credit_balance do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @sponsorable)
        listing = @sponsorable.sponsors_listing
        assert_predicate sponsorship, :sponsors_invoiced?

        reset_hydro

        result = sponsorship.cancel(actor: invoiced_org.admin, force: true)

        assert result.success
        message = {
          actor: Hydro::EntitySerializer.user(invoiced_org.admin),
          request_context: nil,
          sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
          listing: Hydro::EntitySerializer.sponsors_listing(listing),
          tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
          matchable: false,
          action: :CANCEL,
          first_time_sponsor: false,
          first_time_sponsorable: false,
          invoiced: true,
          listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
            listing.stafftools_metadata,
          ),
          payment_source: :GITHUB,
        }
        assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      end
    end

    skip "temporary while Sponsors team fixes flaky test see https://github.com/github/github/issues/345332" do
      test "rolls back Sponsorship deactivation + expiration when subscription item deactivation fails" do
        sponsorship = create(:sponsorship, tier: @one_time_tier, sponsor: @sponsor, sponsorable: @sponsorable,
          expires_at: 1.month.from_now)
        old_expires_at = sponsorship.expires_at
        Billing::SubscriptionItem.any_instance.stubs(:deactivate_without_callbacks).returns(false)

        result = travel_to(1.week.from_now) do
          sponsorship.cancel(actor: @sponsor)
        end

        refute_nil result
        refute result.success
        assert_predicate sponsorship.reload, :active?
        assert_predicate sponsorship.reload_subscription_item, :active?
        assert_equal old_expires_at, sponsorship.expires_at
      end
    end

    test "does not deactivate subscription item when sponsorship fails to deactivate and expire" do
      sponsorship = create(:sponsorship, tier: @one_time_tier, sponsor: @sponsor, sponsorable: @sponsorable,
        expires_at: 1.month.from_now)
      sponsorship.stubs(:deactivate_and_expire_without_callbacks).returns(false)

      result = sponsorship.cancel(actor: @sponsor)

      refute_nil result
      refute result.success
      assert_predicate sponsorship.reload, :active?
      assert_predicate sponsorship.reload_subscription_item, :active?
    end
  end

  context "#enqueue_pending_sponsorship_email_job" do
    test "enqueues a job to email sponsors if sponsorship's state is pending when FF enabled" do
      @sponsor.enable_feature(:sponsors_pending_sponsorships)

      pending_sponsorship = create(:sponsorship, :pending, tier: @recurring_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)

      assert_enqueued_with(
        job: SendPendingSponsorshipEmailJob,
        args: [pending_sponsorship],
      ) do
        pending_sponsorship.enqueue_pending_sponsorship_email_job
      end
    end

    test "does not enqueue a job to email sponsors if sponsorship's state is pending when FF disabled" do
      @sponsor.disable_feature(:sponsors_pending_sponsorships)

      pending_sponsorship = create(:sponsorship, :pending, tier: @recurring_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)

      assert_no_enqueued_jobs(only: SendPendingSponsorshipEmailJob) do
        pending_sponsorship.enqueue_pending_sponsorship_email_job
      end
    end

    test "does not enqueue a job to email sponsors if sponsorship's state is active when FF enabled" do
      @sponsor.enable_feature(:sponsors_pending_sponsorships)

      active_sponsorship = create(:sponsorship, tier: @recurring_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)

      assert_no_enqueued_jobs(only: SendPendingSponsorshipEmailJob) do
        active_sponsorship.enqueue_pending_sponsorship_email_job
      end
    end
  end

  context "#enqueue_revoke_repository_access_job" do
    test "enqueues a job to revoke the sponsor's repo access when a SponsorshipRepository exists" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @tier_with_repo)
      create(:sponsorship_repository, sponsor: @sponsor, sponsors_tier: @tier_with_repo,
        repository: @tier_with_repo.repository, sponsorable: @sponsorable)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [@sponsor.id, @tier_with_repo.repository_id, @tier_with_repo.id],
      ) do
        sponsorship.enqueue_revoke_repository_access_job
      end
    end

    test "enqueues a job for the repo that was granted, not the tier's current repo" do
      other_repo = create(:private_repository, :org_owned)
      other_repo.add_member(@sponsorable, action: :admin)

      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @tier_with_repo)
      repo_granted = @tier_with_repo.repository
      create(:sponsorship_repository, sponsor: @sponsor, sponsors_tier: @tier_with_repo,
        repository: repo_granted, sponsorable: @sponsorable)

      @tier_with_repo.update!(repository: other_repo)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [@sponsor.id, repo_granted.id, @tier_with_repo.id],
      ) do
        sponsorship.enqueue_revoke_repository_access_job
      end
    end

    test "does not enqueue a job when no SponsorshipRepository exists" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @tier_with_repo)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        sponsorship.enqueue_revoke_repository_access_job
      end
    end
  end

  context ".total_recurring_monthly_price_in_cents" do
    test "sums recurring sponsorships in a given array" do
      recurring_sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)
      one_time_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @one_time_tier)
      recurring_sponsorship2 = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      refute_equal @recurring_tier.monthly_price_in_cents, @one_time_tier.monthly_price_in_cents,
        "need a one-time tier and a recurring tier with different prices"

      result = Sponsorship.total_recurring_monthly_price_in_cents([
        recurring_sponsorship1,
        one_time_sponsorship,
        recurring_sponsorship2,
      ], viewer: @sponsorable)

      assert_equal @recurring_tier.monthly_price_in_cents * 2, result
    end

    test "sums recurring sponsorships in a given scope" do
      recurring_sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)
      one_time_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @one_time_tier)
      recurring_sponsorship2 = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      refute_equal @recurring_tier.monthly_price_in_cents, @one_time_tier.monthly_price_in_cents,
        "need a one-time tier and a recurring tier with different prices"

      result = Sponsorship.total_recurring_monthly_price_in_cents(Sponsorship.where(id: [
        recurring_sponsorship1,
        one_time_sponsorship,
        recurring_sponsorship2,
      ]), viewer: @sponsorable)

      assert_equal @recurring_tier.monthly_price_in_cents * 2, result
    end

    test "can include non-Zuora invoiced sponsorships and recurring sponsorships in a given scope" do
      recurring_sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)
      recurring_sponsorship2 = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      transfer = create(:invoiced_sponsorship_transfer, sponsors_listing: @listing)
      invoiced_sponsorship = create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

      result = Sponsorship.total_recurring_monthly_price_in_cents(
        Sponsorship.where(id: [
          recurring_sponsorship1,
          recurring_sponsorship2,
          invoiced_sponsorship,
        ]),
        viewer: @sponsorable,
        include_invoiced: true
      )

      expected_total = @recurring_tier.monthly_price_in_cents * 2 + invoiced_sponsorship.monthly_price_in_cents
      assert_equal expected_total, result
    end

    test "can include non-Zuora invoiced sponsorships and recurring sponsorships in a given scope passed as an array" do
      recurring_sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)
      recurring_sponsorship2 = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      transfer = create(:invoiced_sponsorship_transfer, sponsors_listing: @listing)
      invoiced_sponsorship = create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

      result = Sponsorship.total_recurring_monthly_price_in_cents(
        [
          recurring_sponsorship1,
          recurring_sponsorship2,
          invoiced_sponsorship,
        ],
        viewer: @sponsorable,
        include_invoiced: true
      )

      expected_total = @recurring_tier.monthly_price_in_cents * 2 + invoiced_sponsorship.monthly_price_in_cents
      assert_equal expected_total, result
    end

    test "respects the original scopes when invoiced sponsorships are included" do
      stub_credit_balance do
        org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        admin = org.admins.first
        sponsorship = create(:sponsorship, :invoiced, sponsor: org, monthly_price_in_cents: 3000)
        create(:sponsorship, sponsor: org, monthly_price_in_cents: 1000)

        scope = org.sponsorships_as_sponsor.where.not(id: sponsorship.id)

        result = Sponsorship.total_recurring_monthly_price_in_cents(scope, viewer: admin, include_invoiced: true)

        assert_equal 1000, result
      end
    end
  end

  context ".total_recurring_monthly_price_in_dollars" do
    test "sums recurring sponsorships in a given array" do
      recurring_sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)
      one_time_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @one_time_tier)
      recurring_sponsorship2 = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      refute_equal @recurring_tier.monthly_price_in_cents, @one_time_tier.monthly_price_in_cents,
        "need a one-time tier and a recurring tier with different prices"

      result = Sponsorship.total_recurring_monthly_price_in_dollars([
        recurring_sponsorship1,
        one_time_sponsorship,
        recurring_sponsorship2,
      ], viewer: @sponsorable)

      assert_equal @recurring_tier.monthly_price_in_dollars.to_i * 2, result
    end

    test "sums recurring sponsorships in a given scope" do
      recurring_sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)
      one_time_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @one_time_tier)
      recurring_sponsorship2 = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      refute_equal @recurring_tier.monthly_price_in_cents, @one_time_tier.monthly_price_in_cents,
        "need a one-time tier and a recurring tier with different prices"

      result = Sponsorship.total_recurring_monthly_price_in_dollars(Sponsorship.where(id: [
        recurring_sponsorship1,
        one_time_sponsorship,
        recurring_sponsorship2,
      ]), viewer: @sponsorable)

      assert_equal @recurring_tier.monthly_price_in_dollars.to_i * 2, result
    end
  end

  context "#async_sponsor_entity" do
    test "resolves to nil when sponsor is not readable by viewer" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)

      promise = sponsorship.async_sponsor_entity(viewer: @rando)

      assert_nil promise.sync
    end

    test "resolves to user sponsor when sponsor is readable by viewer" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      promise = sponsorship.async_sponsor_entity(viewer: @sponsorable)
      assert_equal @sponsor, promise.sync
    end

    test "resolves to org sponsor when sponsor is readable by viewer" do
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      promise = sponsorship.async_sponsor_entity(viewer: nil)
      assert_equal sponsorship.sponsor, promise.sync
    end

    test "resolves to linked org sponsor when sponsor is readable by viewer" do
      linked_org = create(:organization)
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      create(:organization_profile, organization: linked_org,
         sponsoring_linked_organization: sponsorship.sponsor)

      promise = sponsorship.async_sponsor_entity(viewer: nil)

      assert_equal linked_org, promise.sync
    end
  end

  context "#linked_or_direct_sponsor" do
    test "returns user sponsor" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      assert_equal @sponsor, sponsorship.linked_or_direct_sponsor
    end

    test "returns direct org sponsor when there is no sponsoring linked org" do
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      assert_equal sponsorship.sponsor, sponsorship.linked_or_direct_sponsor
    end

    test "returns sponsoring linked org when it exists for org sponsor" do
      linked_org = create(:organization)
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      create(:organization_profile, organization: linked_org,
        sponsoring_linked_organization: sponsorship.sponsor)

      assert_equal linked_org, sponsorship.linked_or_direct_sponsor
    end

    test "returns ghost user when sponsor is deleted" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      sponsorship.update(sponsor: nil)

      assert_equal User.ghost, sponsorship.linked_or_direct_sponsor
    end
  end

  context "#blocked_for?" do
    test "false when neither the sponsor nor the sponsorable are blocking each other" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      refute sponsorship.blocked_for?(@rando)
    end

    # https://github.com/github/sponsors/issues/5467
    test "false when sponsor is nil" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable)
      sponsorship.sponsor.delete
      refute sponsorship.reload.blocked_for?(@rando)
    end

    # https://github.com/github/sponsors/issues/5467
    test "false for anonymous viewer even when sponsor is nil" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable)
      sponsorship.sponsor.delete
      refute sponsorship.reload.blocked_for?(nil)
    end

    test "true when the sponsor is blocking the sponsorable and current user is not sponsor or sponsorable" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)
      assert sponsorship.blocked_for?(@rando)
    end

    test "true when the sponsor is blocking the sponsorable and current user is the sponsor" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)
      assert sponsorship.blocked_for?(@sponsor)
    end

    test "false when the sponsor is blocking the sponsorable and current user is the sponsorable" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsor.block(@sponsorable)
      refute sponsorship.blocked_for?(@sponsorable)
    end

    test "true when the sponsorable is blocking the sponsor and current user is not sponsor or sponsorable" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsorable.block(@sponsor)
      assert sponsorship.blocked_for?(@rando)
    end

    test "true when the sponsorable is blocking the sponsor and current user is the sponsorable" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsorable.block(@sponsor)
      assert sponsorship.blocked_for?(@sponsorable)
    end

    test "false when the sponsorable is blocking the sponsor and current user is the sponsor" do
      sponsorship = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      @sponsorable.block(@sponsor)
      refute sponsorship.blocked_for?(@sponsor)
    end

    test "can be prefilled to avoid N+1 queries" do
      sponsorship1 = create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      sponsorship2 = @basic_sponsorship
      sponsorship2.sponsor.block(sponsorship2.sponsorable)

      # Load the sponsorships fresh so the sponsor and sponsorable relations haven't been loaded:
      sponsorships_by_id = Sponsorship.where(id: [sponsorship1, sponsorship2]).index_by(&:id)

      expected_queries_per_table = { ignored_users: 1, users: 1 }

      assert_query_count(expected_queries_per_table.values.sum) do
        assert_query_count_per_table(expected_queries_per_table) do
          GitHub::PrefillAssociations.prefill_batch_method(sponsorships_by_id.values, :blocked_for?, @rando)
        end
      end

      assert_query_count 0 do
        refute sponsorships_by_id[sponsorship1.id].blocked_for?(@rando)
        assert sponsorships_by_id[sponsorship2.id].blocked_for?(@rando)
      end
    end
  end

  context ".sponsor_and_tier_ids_with_line_items" do
    test "returns paired sponsor IDs and tier IDs for sponsorship billing line items" do
      sponsorship1 = @basic_sponsorship
      transaction1 = create(:billing_transaction, user: sponsorship1.sponsor,
        amount_in_cents: sponsorship1.tier.monthly_price_in_cents)
      line_item1 = create(:billing_transaction_line_item, quantity: 1,
        billing_transaction: transaction1, subscribable: sponsorship1.tier,
        amount_in_cents: sponsorship1.tier.monthly_price_in_cents,
        description: "GitHub Sponsors - #{sponsorship1.sponsorable} sponsorship")

      sponsorship2 = create(:sponsorship)
      transaction2 = create(:billing_transaction, user: sponsorship2.sponsor,
        amount_in_cents: sponsorship2.tier.monthly_price_in_cents)
      line_item2 = create(:billing_transaction_line_item, quantity: 1,
        billing_transaction: transaction2, subscribable: sponsorship2.tier,
        amount_in_cents: sponsorship2.tier.monthly_price_in_cents,
        description: "GitHub Sponsors - #{sponsorship2.sponsorable} sponsorship")
      line_item3 = create(:billing_transaction_line_item, quantity: 1,
        billing_transaction: transaction2, subscribable: sponsorship2.tier,
        amount_in_cents: sponsorship2.tier.monthly_price_in_cents,
        description: "GitHub Sponsors - #{sponsorship2.sponsorable} sponsorship")

      sponsor_ids_to_check = [
        sponsorship1.sponsor_id,
        @sponsor.id,
        @staff.id,
        sponsorship2.sponsor_id,
        @spammy_user&.id,
      ]
      tier_ids_to_check = [
        @recurring_tier.id,
        sponsorship2.subscribable_id,
        @one_time_tier.id,
        sponsorship1.subscribable_id,
      ]

      sponsor_and_tier_ids = Sponsorship.sponsor_and_tier_ids_with_line_items(
        sponsor_ids_to_check,
        tier_ids_to_check,
      )

      assert_equal 2, sponsor_and_tier_ids.size
      sponsor_and_tier_ids.each do |sponsor_id, tier_id|
        assert Sponsorship.where(id: [sponsorship1, sponsorship2])
          .exists?(sponsor_id: sponsor_id, subscribable_id: tier_id)
      end
    end
  end

  context "#latest_billing_transaction_line_item_for_tier" do
    test "returns the most recent line item for the sponsorship's current tier" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      old_date = 1.month.ago
      transaction = travel_to(old_date) do
        create(:billing_transaction, user: @sponsor, amount_in_cents: @recurring_tier.monthly_price_in_cents)
      end
      travel_to(old_date) do
        create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction,
          subscribable: @recurring_tier, amount_in_cents: @recurring_tier.monthly_price_in_cents)
      end
      new_line_item = create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction,
        subscribable: @recurring_tier, amount_in_cents: @recurring_tier.monthly_price_in_cents)

      assert_equal new_line_item, sponsorship.latest_billing_transaction_line_item_for_tier
    end

    test "will not return line item for the same sponsor+sponsorable but using a different tier" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      transaction = create(:billing_transaction, user: @sponsor,
        amount_in_cents: @one_time_tier.monthly_price_in_cents)
      line_item = create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: @one_time_tier, amount_in_cents: @one_time_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{@sponsorable} sponsorship")

      assert_nil sponsorship.latest_billing_transaction_line_item_for_tier
    end

    test "can be batch loaded" do
      sponsorship1, sponsorship2, sponsorship3 = create_list(:sponsorship, 3)

      # First sponsorship:
      xact1 = create(:billing_transaction, user: sponsorship1.sponsor,
        amount_in_cents: sponsorship1.tier.monthly_price_in_cents)
      line_item1 = create(:billing_transaction_line_item, :sponsors, billing_transaction: xact1,
        subscribable: sponsorship1.tier)

      # Second sponsorship:
      create(:billing_transaction, user: sponsorship2.sponsor, # won't have a line item
        amount_in_cents: sponsorship2.tier.monthly_price_in_cents)

      # Third sponsorship:
      travel_to(3.months.ago) do
        xact = create(:billing_transaction, user: sponsorship3.sponsor,
          amount_in_cents: sponsorship3.tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, :sponsors, billing_transaction: xact, subscribable: sponsorship3.tier)
      end
      travel_to(2.months.ago) do
        xact = create(:billing_transaction, user: sponsorship3.sponsor,
          amount_in_cents: sponsorship3.tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, :sponsors, billing_transaction: xact, subscribable: sponsorship3.tier)
      end
      xact = create(:billing_transaction, user: sponsorship3.sponsor,
        amount_in_cents: sponsorship3.tier.monthly_price_in_cents)
      line_item3 = create(:billing_transaction_line_item, :sponsors, billing_transaction: xact,
        subscribable: sponsorship3.tier)

      sponsorships = [sponsorship1, sponsorship2, sponsorship3]

      assert_query_count_per_table({ billing_transaction_line_items: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :latest_billing_transaction_line_item_for_tier)
      end

      assert_query_count(0) do
        assert_equal line_item1, sponsorship1.latest_billing_transaction_line_item_for_tier
        assert_nil sponsorship2.latest_billing_transaction_line_item_for_tier
        assert_equal line_item3, sponsorship3.latest_billing_transaction_line_item_for_tier
      end
    end
  end

  context "#billing_transaction_line_items" do
    test "returns the sponsorship's line items" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      transaction = create(:billing_transaction, user: @sponsor,
        amount_in_cents: @recurring_tier.monthly_price_in_cents)
      line_items = create_list(:billing_transaction_line_item, 2, billing_transaction: transaction,
        subscribable: @recurring_tier, amount_in_cents: @recurring_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{@sponsorable} sponsorship")

      assert_same_elements line_items, sponsorship.billing_transaction_line_items
    end

    test "includes line item for the same sponsor+sponsorable but using a different tier" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      transaction = create(:billing_transaction, user: @sponsor,
        amount_in_cents: @one_time_tier.monthly_price_in_cents)
      line_item = create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: @one_time_tier, amount_in_cents: @one_time_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{@sponsorable} sponsorship")

      assert_equal [line_item], sponsorship.billing_transaction_line_items
    end

    test "omits line item for a tier belonging to a sponsorable different than the sponsorship" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      transaction = create(:billing_transaction, user: @sponsor,
        amount_in_cents: @recurring_tier.monthly_price_in_cents)
      unrelated_tier = create(:sponsors_tier, :approved_sponsors_listing)
      create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: unrelated_tier, amount_in_cents: unrelated_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{@sponsorable} sponsorship")

      assert_empty sponsorship.billing_transaction_line_items
    end

    test "omits line item for a different user than the sponsorship's sponsor" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      transaction = create(:billing_transaction, user: @rando,
        amount_in_cents: @recurring_tier.monthly_price_in_cents)
      create(:billing_transaction_line_item, billing_transaction: transaction,
        subscribable: @recurring_tier, amount_in_cents: @recurring_tier.monthly_price_in_cents,
        quantity: 1, description: "GitHub Sponsors - #{@sponsorable} sponsorship")

      assert_empty sponsorship.billing_transaction_line_items
    end
  end

  context "latest_one_time_payment_activity" do
    test "gets the most recent one-time payment SponsorsActivity when there are multiple" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @one_time_tier,
        sponsor: @sponsor)
      second_one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: @listing)

      travel_to 1.minute.ago do
        create(:sponsors_activity, :new_sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, sponsors_tier: @one_time_tier)
      end
      second_activity = create(:sponsors_activity, :new_sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, sponsors_tier: second_one_time_tier)

      assert_equal second_activity, sponsorship.latest_one_time_payment_activity
    end

    test "returns nil when there were no new_sponsorship SponsorsActivitys" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)

      assert_nil sponsorship.latest_one_time_payment_activity
    end

    test "returns nil when there is only a recurring new_sponsorship SponsorsActivity" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      create(:sponsors_activity, :new_sponsorship, sponsors_tier: @recurring_tier, sponsorable: @sponsorable, sponsor: @sponsor,)

      assert_nil sponsorship.latest_one_time_payment_activity
    end
  end

  context "tier_selected_before scope" do
    test "includes sponsorships whose tier was chosen before the given time" do
      cutoff_time = Time.now
      sponsorship1 = travel_to(cutoff_time - 1.day) do
        create(:sponsorship, tier: @recurring_tier, sponsor: @sponsor,
          sponsorable: @sponsorable)
      end
      sponsorship2 = travel_to(cutoff_time + 1.day) do
        create(:sponsorship, tier: @recurring_tier, sponsorable: @sponsorable)
      end

      result = Sponsorship.where(id: [sponsorship1, sponsorship2]).tier_selected_before(cutoff_time)

      assert_includes result, sponsorship1
      refute_includes result, sponsorship2
    end
  end

  context "#sponsor_counts_by_listing_id" do
    test "returns a hash with sponsor counts for the requested listings" do
      create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      create(:sponsorship, sponsorable: @sponsorable)
      other_sponsorship = create(:sponsorship, sponsor: @sponsor)

      # Shouldn't be counted because inactive:
      create(:sponsorship, :inactive, sponsorable: @sponsorable)

      # Not going to look up this listing:
      another_sponsorship = create(:sponsorship, sponsor: @sponsor)

      result = Sponsorship.sponsor_counts_by_listing_id([
        @listing.id, other_sponsorship.sponsors_listing.id
      ], viewer: nil)

      assert_equal 2, result[@listing.id],
        "should not have counted the 1 inactive sponsorship"
      assert_equal 0, result[another_sponsorship.sponsors_listing.id],
        "should not have looked up sponsorships for a listing we didn't request"
      assert_equal 1, result[other_sponsorship.sponsors_listing.id]
    end

    test "does not count sponsorship from spammer" do
      spammy_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @spammy_user)

      result = Sponsorship.sponsor_counts_by_listing_id([@listing.id], viewer: nil)

      assert_equal 0, result[@listing.id]
    end if GitHub.spamminess_check_enabled?
  end

  context "#from_organization?" do
    test "true when sponsor is an org" do
      sponsorship = build(:sponsorship, :from_org)
      assert_predicate sponsorship, :from_organization?
    end

    test "false when sponsor is a user" do
      sponsorship = build(:sponsorship)
      refute_predicate sponsorship, :from_organization?
    end
  end

  context "#to_organization?" do
    test "true when sponsorable is an org" do
      sponsorship = build(:sponsorship, :with_org_sponsorable)
      assert_predicate sponsorship, :to_organization?
    end

    test "false when sponsorable is a user" do
      sponsorship = build(:sponsorship)
      refute_predicate sponsorship, :to_organization?
    end
  end

  context "#to_user?" do
    test "true when sponsorable is a user" do
      assert_predicate @sponsorable, :user?, "need a user"
      sponsorship = build(:sponsorship, sponsorable: @sponsorable)
      assert_predicate sponsorship, :to_user?
    end

    test "false when sponsorable is an organization" do
      sponsorship = build(:sponsorship, :with_org_sponsorable)
      refute_predicate sponsorship, :to_user?
    end
  end

  context "#monthly_price_in_dollars" do
    test "returns the monthly price in dollars from the subscribable" do
      tier = build(:sponsors_tier, monthly_price_in_cents: 10_00)
      sponsorship = build(:sponsorship, tier: tier)
      assert_equal 10, sponsorship.monthly_price_in_dollars
    end
  end

  context "#custom_tier?" do
    test "true when subscribable is a custom one" do
      tier = build(:sponsors_tier, :custom)
      sponsorship = build(:sponsorship, tier: tier)
      assert_predicate sponsorship, :custom_tier?
    end

    test "false when subscribable is not custom" do
      tier = build(:sponsors_tier)
      sponsorship = build(:sponsorship, tier: tier)
      refute_predicate sponsorship, :custom_tier?
    end
  end

  context "#tier_creator" do
    test "returns creator of the subscribable" do
      creator = build(:user)
      tier = build(:sponsors_tier, creator: creator)
      sponsorship = build(:sponsorship, tier: tier)
      assert_equal creator, sponsorship.tier_creator
    end
  end

  context "#async_hide_from_user?" do
    test "true for spammy sponsor and anonymous viewer" do
      sponsorship = build(:sponsorship, sponsor: @spammy_user, sponsorable: @sponsorable)
      assert sponsorship.async_hide_from_user?(nil).sync
    end

    test "false for spammy sponsor and staff viewer" do
      sponsorship = build(:sponsorship, sponsor: @spammy_user, sponsorable: @sponsorable)
      refute sponsorship.async_hide_from_user?(@staff).sync
    end

    test "false for spammy sponsor when they're the viewer" do
      sponsorship = build(:sponsorship, sponsor: @spammy_user, sponsorable: @sponsorable)
      refute sponsorship.async_hide_from_user?(@spammy_user).sync
    end

    test "false for spammy org sponsor when viewer is the org admin" do
      sponsorship = build(:sponsorship, sponsor: @spammy_org, sponsorable: @sponsorable)
      refute sponsorship.async_hide_from_user?(@spammy_org.admins.first).sync
    end

    test "true for spammy sponsorable and anonymous viewer" do
      sponsorship = build(:sponsorship, sponsorable: @spammy_user, sponsor: @sponsor)
      assert sponsorship.async_hide_from_user?(nil).sync
    end

    test "false for spammy sponsorable and staff viewer" do
      sponsorship = build(:sponsorship, sponsorable: @spammy_user, sponsor: @sponsor)
      refute sponsorship.async_hide_from_user?(@staff).sync
    end

    test "false for spammy sponsorable when they're the viewer" do
      sponsorship = build(:sponsorship, sponsorable: @spammy_user, sponsor: @sponsor)
      refute sponsorship.async_hide_from_user?(@spammy_user).sync
    end

    test "false for spammy org sponsorable when viewer is the org admin" do
      sponsorship = build(:sponsorship, sponsorable: @spammy_org, sponsor: @sponsor)
      refute sponsorship.async_hide_from_user?(@spammy_org.admins.first).sync
    end
  end if GitHub.spamminess_check_enabled?

  context "filter_spam_for scope" do
    test "filters out sponsorships from spammy sponsors where appropriate" do
      sponsorship1 = create(:sponsorship, sponsor: @spammy_org, sponsorable: @sponsorable)
      sponsorship2 = create(:sponsorship, sponsor: @spammy_user, sponsorable: @sponsorable)

      assert_empty Sponsorship.where(id: [sponsorship1, sponsorship2]).filter_spam_for(nil),
        "shouldn't show sponsorship from spammy sponsor to anonymous viewer"
      assert_empty Sponsorship.where(id: [sponsorship1, sponsorship2]).filter_spam_for(@rando),
        "shouldn't show sponsorship from spammy sponsor to regular viewer"
      assert_same_elements [sponsorship1, sponsorship2], Sponsorship.where(id: [sponsorship1, sponsorship2])
        .filter_spam_for(@staff), "should show sponsorship from spammy sponsor to staff viewer"
      assert_equal [sponsorship2], Sponsorship.where(id: [sponsorship1, sponsorship2])
        .filter_spam_for(@spammy_user), "should show to themselves a sponsorship from a spammy sponsor"
    end

    test "filters out sponsorships of spammy sponsorables where appropriate" do
      sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @spammy_org)
      sponsorship2 = create(:sponsorship, sponsor: @sponsor, sponsorable: @spammy_user)

      assert_empty Sponsorship.where(id: [sponsorship1, sponsorship2]).filter_spam_for(nil),
        "shouldn't show sponsorship of spammy maintainer to anonymous viewer"
      assert_empty Sponsorship.where(id: [sponsorship1, sponsorship2]).filter_spam_for(@rando),
        "shouldn't show sponsorship of spammy maintainer to regular viewer"
      assert_same_elements [sponsorship1, sponsorship2], Sponsorship.where(id: [sponsorship1, sponsorship2])
        .filter_spam_for(@staff), "should show sponsorship of spammy maintainer to staff viewer"
      assert_equal [sponsorship2], Sponsorship.where(id: [sponsorship1, sponsorship2])
        .filter_spam_for(@spammy_user), "should show sponsorship of spammy maintainer to themselves"
    end

    test "limits queries made" do
      sponsorship1 = create(:sponsorship, sponsor: @spammy_org, sponsorable: @sponsorable)
      sponsorship2 = create(:sponsorship, sponsor: @sponsor, sponsorable: @spammy_user)
      sponsorship3 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      expected_queries = { users: 1, sponsorships: 1 }
      assert_query_count_per_table(expected_queries) do
        assert_query_count(expected_queries.values.sum) do
          Sponsorship.where(id: [sponsorship1, sponsorship2, sponsorship3]).filter_spam_for(nil)
        end
      end
    end
  end if GitHub.spamminess_check_enabled?

  context "without_custom_tiers scope" do
    test "includes only sponsorships whose subscribable is not a custom tier" do
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @listing)
      custom_sponsorship = create(:sponsorship, tier: custom_tier)
      non_custom_sponsorship = create(:sponsorship, tier: @listing.default_tier)

      result = Sponsorship.without_custom_tiers
        .where(id: [custom_sponsorship, non_custom_sponsorship])

      assert_includes result, non_custom_sponsorship
      refute_includes result, custom_sponsorship
    end
  end

  context "one_time scope" do
    test "includes only sponsorships whose subscribable is a one-time tier" do
      one_time_sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)
      recurring_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)

      result = Sponsorship.one_time
        .where(id: [one_time_sponsorship, recurring_sponsorship])

      assert_includes result, one_time_sponsorship
      refute_includes result, recurring_sponsorship
    end
  end

  context "recurring scope" do
    test "includes only sponsorships whose subscribable is a recurring tier" do
      one_time_sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)
      recurring_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)

      result = Sponsorship.recurring
        .where(id: [one_time_sponsorship, recurring_sponsorship])

      refute_includes result, one_time_sponsorship
      assert_includes result, recurring_sponsorship
    end
  end

  context "tier_selected_since scope" do
    test "includes only sponsorships where the tier was chosen on or after the given date" do
      old_sponsorship = travel_to(5.days.ago) do
        create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier)
      end
      sponsorship = create(:sponsorship, :unlocked, sponsorable: @sponsorable,
        tier: @recurring_tier)
      new_sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @recurring_tier)

      result = Sponsorship.tier_selected_since(3.days.ago.beginning_of_day)
        .where(id: [old_sponsorship, sponsorship, new_sponsorship])

      assert_includes result, new_sponsorship
      assert_includes result, sponsorship
      refute_includes result, old_sponsorship
    end
  end

  context "#locked?" do
    test "true for sponsorship with one-time tier that was chosen within the last 2 days" do
      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @one_time_tier)
      assert_predicate sponsorship, :locked?
    end

    test "false for sponsorship with a recurring tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier)
      refute_predicate sponsorship, :locked?
    end

    test "false for sponsorship that was created >2 days ago with one-time tier" do
      sponsorship = create(:sponsorship, :unlocked, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)
      refute_predicate sponsorship, :locked?
    end

    test "false when sponsorship's one-time tier was chosen more than 2 days ago" do
      sponsorship = travel_to(4.days.ago) do
        create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      end
      assert_predicate sponsorship, :recurring_payment?
      refute_predicate sponsorship, :locked?

      travel_to((Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days.ago) do
        sponsorship.update!(tier: @one_time_tier, expires_at: Sponsorship.expiration_time,
          subscribable_selected_at: Time.now)

        assert_predicate sponsorship, :one_time_payment?
        assert_predicate sponsorship, :locked?
      end

      refute_predicate sponsorship, :locked?
    end

    test "false for sponsorship with one-time invoiced tier" do
      sponsorship = create(:sponsorship, :invoiced)
      refute_predicate sponsorship, :locked?
    end
  end

  context "locked scope" do
    test "includes only sponsorships that are locked" do
      locked_sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @one_time_tier)
      assert_predicate locked_sponsorship, :locked?
      unlocked_sponsorship = create(:sponsorship, sponsorable: @sponsorable,
        tier: @recurring_tier)
      refute_predicate unlocked_sponsorship, :locked?
      invoiced_sponsorship = create(:sponsorship, :invoiced)
      refute_predicate invoiced_sponsorship, :locked?

      result = Sponsorship.locked
        .where(id: [locked_sponsorship, unlocked_sponsorship, invoiced_sponsorship])

      assert_includes result, locked_sponsorship
      refute_includes result, unlocked_sponsorship
      refute_includes result, invoiced_sponsorship
    end
  end

  context "only_custom_tiers scope" do
    test "includes only sponsorships whose subscribable is a custom tier" do
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @listing)
      custom_sponsorship = create(:sponsorship, tier: custom_tier)
      non_custom_sponsorship = create(:sponsorship, tier: @listing.default_tier)

      result = Sponsorship.only_custom_tiers
        .where(id: [custom_sponsorship, non_custom_sponsorship])

      refute_includes result, non_custom_sponsorship
      assert_includes result, custom_sponsorship
    end
  end

  context "sponsor_visible_to scope" do
    test "includes private sponsorship from org for org admin viewer" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor

      assert_includes Sponsorship.sponsor_visible_to(org.admins.first), sponsorship
    end

    test "includes private sponsorship from linked org for org admin viewer" do
      org_that_gets_credit_admin = create(:user)
      org_that_gets_credit = create(:organization, admin: org_that_gets_credit_admin)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)

      assert_includes Sponsorship.sponsor_visible_to(org_that_gets_credit_admin), sponsorship
    end

    test "includes private sponsorship from org for org billing manager viewer" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      assert_includes Sponsorship.sponsor_visible_to(billing_manager), sponsorship
    end

    test "includes private sponsorship from linked org for org billing manager viewer" do
      org_that_gets_credit = create(:organization)
      org_that_gets_credit_billing_manager = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_manager,
        actor: org_that_gets_credit.admin)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)

      assert_includes Sponsorship.sponsor_visible_to(org_that_gets_credit_billing_manager), sponsorship
    end

    test "includes private sponsorship to org for org admin viewer" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable

      assert_includes Sponsorship.sponsor_visible_to(org.admins.first), sponsorship
    end

    test "omits private sponsorship to org for org billing manager viewer" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      refute_includes Sponsorship.sponsor_visible_to(billing_manager), sponsorship
    end

    test "includes private sponsorship from org for org member viewer" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      assert_includes Sponsorship.sponsor_visible_to(org_member), sponsorship
    end

    test "includes private sponsorship from linked org for org member viewer" do
      org_that_gets_credit = create(:organization)
      org_that_gets_credit_member = create(:user)
      org_that_gets_credit.add_member(org_that_gets_credit_member)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)

      assert_includes Sponsorship.sponsor_visible_to(org_that_gets_credit_member), sponsorship
    end

    test "includes private sponsorship to org for org member viewer" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      org_member = create(:user)
      org.add_member(org_member)

      assert_includes Sponsorship.sponsor_visible_to(org_member), sponsorship
    end

    test "includes private sponsorship from org using a custom tier made by a different user for an org admin" do
      org_admin = create(:user)
      billing_manager = create(:user)

      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
        admin: org_admin)
      org.billing.add_manager(billing_manager, actor: org_admin)

      custom_tier = create(:sponsors_tier, :custom, creator: billing_manager,
        sponsors_listing: @listing)

      sponsorship = create(:sponsorship, :private, sponsor: org, tier: custom_tier,
        sponsorable: @sponsorable)
      assert_includes Sponsorship.sponsor_visible_to(org_admin), sponsorship
    end

    test "includes private sponsorship from org using a custom tier made by a different user for a billing manager" do
      org_admin = create(:user)
      billing_manager = create(:user)

      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
        admin: org_admin)
      org.billing.add_manager(billing_manager, actor: org_admin)

      custom_tier = create(:sponsors_tier, :custom, creator: org_admin,
        sponsors_listing: @listing)

      sponsorship = create(:sponsorship, :private, sponsor: org, tier: custom_tier,
        sponsorable: @sponsorable)
      assert_includes Sponsorship.sponsor_visible_to(billing_manager), sponsorship
    end

    test "does not include private sponsorship from org for non-org member viewer" do
      sponsorship = create(:sponsorship, :private, :from_org)
      refute_includes Sponsorship.sponsor_visible_to(@rando), sponsorship
    end

    test "does not include private sponsorship to org for non-org member viewer" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      refute_includes Sponsorship.sponsor_visible_to(@rando), sponsorship
    end

    test "does not include private sponsorship to org for anonymous viewer" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      refute_includes Sponsorship.sponsor_visible_to(nil), sponsorship
    end

    test "includes public sponsorship for anonymous viewer" do
      assert_includes Sponsorship.sponsor_visible_to(nil), @basic_sponsorship
    end

    test "includes private sponsorship for its sponsor" do
      sponsorship = create(:sponsorship, :private)
      assert_includes Sponsorship.sponsor_visible_to(sponsorship.sponsor), sponsorship
    end

    test "includes private sponsorship for its sponsored maintainer" do
      sponsorship = create(:sponsorship, :private)
      assert_includes Sponsorship.sponsor_visible_to(sponsorship.sponsorable), sponsorship
    end

    test "does not include private sponsorship for a viewer who is not involved" do
      sponsorship = create(:sponsorship, :private)
      refute_includes Sponsorship.sponsor_visible_to(@rando), sponsorship
    end

    test "does not include private sponsorship for an anonymous viewer" do
      sponsorship = create(:sponsorship, :private)
      refute_includes Sponsorship.sponsor_visible_to(nil), sponsorship
    end

    test "respects given linked_org_sponsor_ids_by_org_id hash for org member" do
      org_that_gets_credit = create(:organization)
      org_that_gets_credit_member = create(:user)
      org_that_gets_credit.add_member(org_that_gets_credit_member)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      private_sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)

      refute_includes Sponsorship.sponsor_visible_to(org_that_gets_credit_member), private_sponsorship,
        "should not return private sponsorship when orgs aren't linked"

      result = Sponsorship.sponsor_visible_to(org_that_gets_credit_member,
        linked_org_sponsor_ids_by_org_id: { org_that_gets_credit.id => org_that_pays.id })
      assert_includes result, private_sponsorship, "should return private sponsorship when we say the orgs are linked"
    end

    test "respects given linked_org_sponsor_ids_by_org_id hash for org billing manager" do
      org_that_gets_credit = create(:organization)
      org_that_gets_credit_billing_manager = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_manager,
        actor: org_that_gets_credit.admins.first)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      private_sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)

      refute_includes Sponsorship.sponsor_visible_to(org_that_gets_credit_billing_manager), private_sponsorship,
        "should not return private sponsorship when orgs aren't linked"

      result = Sponsorship.sponsor_visible_to(org_that_gets_credit_billing_manager,
        linked_org_sponsor_ids_by_org_id: { org_that_gets_credit.id => org_that_pays.id })
      assert_includes result, private_sponsorship, "should return private sponsorship when we say the orgs are linked"
    end

    test "looks up linked orgs when given hash is incomplete" do
      org_that_gets_credit1, org_that_gets_credit2 = create_pair(:organization)
      org_that_pays1 = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      org_that_pays2 = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit1,
        sponsoring_linked_organization: org_that_pays1)
      create(:organization_profile, organization: org_that_gets_credit2,
        sponsoring_linked_organization: org_that_pays2)

      private_sponsorship1 = create(:sponsorship, :private, sponsor: org_that_pays1)
      private_sponsorship2 = create(:sponsorship, :private, sponsor: org_that_pays2)

      user = create(:user)
      org_that_gets_credit1.add_member(user)
      org_that_gets_credit2.billing.add_manager(user, actor: org_that_gets_credit2.admins.first)

      result = Sponsorship.sponsor_visible_to(user,
        linked_org_sponsor_ids_by_org_id: { org_that_gets_credit1.id => org_that_pays1.id })
      assert_same_elements [private_sponsorship1, private_sponsorship2, @basic_sponsorship], result,
        "should return both private " \
        "sponsorships when we say one org is linked and it looks up that the other org is linked too"

      result = Sponsorship.sponsor_visible_to(user,
        linked_org_sponsor_ids_by_org_id: { org_that_gets_credit2.id => org_that_pays2.id })
      assert_same_elements [private_sponsorship1, private_sponsorship2, @basic_sponsorship], result,
        "should return both private " \
        "sponsorships when we say one org is linked and it looks up that the other org is linked too"
    end
  end

  context "for_listing scope" do
    test "includes sponsorships that are sponsorsing the specified listing's sponsorable" do
      relevant_sponsorship = create(:sponsorship, sponsorable: @sponsorable)
      unrelated_sponsorship = @basic_sponsorship

      result = Sponsorship.for_listing(@listing)
        .where(id: [relevant_sponsorship, unrelated_sponsorship])

      assert_includes result, relevant_sponsorship
      refute_includes result, unrelated_sponsorship
    end
  end

  context ".sponsors_count_for" do
    test "returns count of sponsors for a given listing" do
      assert_equal 0, Sponsorship.sponsors_count_for(@listing.id)

      create(:sponsorship, sponsorable: @sponsorable)
      assert_equal 1, Sponsorship.sponsors_count_for(@listing.id)

      create(:sponsorship, sponsorable: @sponsorable)
      assert_equal 2, Sponsorship.sponsors_count_for(@listing.id)

      create(:sponsorship, sponsor: @sponsorable)
      assert_equal 2, Sponsorship.sponsors_count_for(@listing.id),
        "should not have increased when new sponsorship was created with the listing's " \
        "sponsorable as the sponsor instead of the one being sponsored"
    end
  end

  context "inactive_scope" do
    test "does not include active sponsorship" do
      result = Sponsorship.inactive.where(id: [@basic_sponsorship])
      assert_empty result
    end

    test "includes inactive sponsorship" do
      sponsorship = create(:sponsorship, :inactive)
      result = Sponsorship.inactive.where(id: [sponsorship])
      assert_equal [sponsorship], result
    end

    test "includes active sponsorships that have expired" do
      sponsorship = create(:sponsorship, :expired)
      result = Sponsorship.inactive.where(id: [sponsorship])
      assert_equal [sponsorship], result
    end
  end

  context "active scope" do
    test "includes active recurring sponsorship" do
      sponsorship = create(:sponsorship, tier: @recurring_tier)
      result = Sponsorship.active.where(id: [sponsorship])
      assert_equal [sponsorship], result
    end

    test "does not include inactive recurring sponsorship" do
      sponsorship = create(:sponsorship, :inactive, tier: @recurring_tier)
      result = Sponsorship.active.where(id: [sponsorship])
      assert_empty result
    end

    # https://github.com/github/sponsors/issues/2430
    test "does not include cancelled one-time sponsorship made in the last 30 days" do
      sponsorship = create(:sponsorship, :inactive, tier: @one_time_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)
      result = Sponsorship.active.where(id: [sponsorship])
      assert_empty result
    end

    test "includes one-time sponsorship made in the last 30 days" do
      sponsorship = travel_to("2021-04-05") do
        create(:sponsorship, tier: @one_time_tier, sponsor: @sponsor,
          sponsorable: @sponsorable)
      end
      travel_to("2021-05-04") do
        result = Sponsorship.active.where(id: [sponsorship])
        assert_equal [sponsorship], result
      end
    end

    test "does not include one-time sponsorship made more than 30 days ago" do
      sponsorship = travel_to(31.days.ago) do
        create(:sponsorship, tier: @one_time_tier, sponsor: @sponsor,
          sponsorable: @sponsorable)
      end
      result = Sponsorship.active.where(id: [sponsorship])
      assert_empty result
    end

    test "includes recurring sponsorship despite its age if it's active" do
      sponsorship = travel_to(6.years.ago) do
        create(:sponsorship, tier: @recurring_tier, sponsor: @sponsor,
          sponsorable: @sponsorable)
      end
      result = Sponsorship.active.where(id: [sponsorship])
      assert_equal [sponsorship], result
    end

    test "includes active invoiced sponsorships" do
      sponsorship = create(:sponsorship, :invoiced, expires_at: 1.month.from_now)
      result = Sponsorship.active.where(id: [sponsorship])

      assert_equal [sponsorship], result
    end

    test "excludes expired invoiced sponsorships" do
      sponsorship = create(:sponsorship, :invoiced, expires_at: 1.month.ago)
      result = Sponsorship.active.where(id: [sponsorship])

      assert_empty result
    end

    test "excludes inactive invoiced sponsorship" do
      sponsorship = create(:sponsorship, :invoiced, expires_at: 1.month.from_now, active: false)
      result = Sponsorship.active.where(id: [sponsorship])

      assert_empty result
    end

    test "excludes recent, inactive one-time sponsorship" do
      sponsorship = create(:sponsorship, :inactive, tier: @one_time_tier)
      refute_predicate sponsorship, :expired?, "want it to only be inactive, not expired"

      assert_empty Sponsorship.active.where(id: [sponsorship])
    end

    test "includes active invoiced sponsorships regardless of when the tier was selected" do
      sponsorship = travel_to(Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.ago - 1.day) do
        create(:sponsorship, :invoiced, expires_at: 6.months.from_now)
      end

      result = Sponsorship.active.where(id: [sponsorship])

      assert_equal [sponsorship], result
    end
  end

  context "listing_approved scope" do
    test "includes sponsorships where the Sponsors listing is approved" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      result = Sponsorship.listing_approved.where(id: [sponsorship])

      assert_equal [sponsorship], result
    end

    test "excludes sponsorships where the Sponsors listing is not approved" do
      GitHub.flipper[:live_sdn_screening].enable(@sponsorable)

      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @listing.sdn_disable!

      assert_empty Sponsorship.listing_approved.where(id: [sponsorship])
    end
  end

  context "#expired?" do
    test "true for one-time sponsorship made >30 days ago" do
      sponsorship = travel_to(31.days.ago) do
        create(:sponsorship, tier: @one_time_tier)
      end
      assert_predicate sponsorship, :expired?
    end

    test "false for one-time sponsorship made within the last 30 days" do
      sponsorship = travel_to(29.days.ago) do
        create(:sponsorship, tier: @one_time_tier)
      end
      refute_predicate sponsorship, :expired?
    end

    test "false for one-time sponsorship made 30 days ago" do
      sponsorship = travel_to(30.days.ago.beginning_of_day) do
        create(:sponsorship, tier: @one_time_tier)
      end
      refute_predicate sponsorship, :expired?
    end

    test "true for invoiced sponsorship that have expired" do
      sponsorship = create(:sponsorship, :invoiced, expires_at: 1.day.ago)

      assert_predicate sponsorship, :expired?
    end

    test "false for invoiced sponsorship that hasn't expired regardless of tier selectiond date" do
      sponsorship = travel_to(31.days.ago) do
        create(:sponsorship, :invoiced, expires_at: 6.months.from_now)
      end

      refute_predicate sponsorship, :expired?
    end
  end

  context "#matchable?" do
    test "true for recurring sponsorship when matching enabled for listing and sponsor allowed" do
      listing = create(:sponsors_listing, :approved, :matchable, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)

      # Date of creation must be at least one month and one day before date
      # of matchable? check
      sponsor = travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 32.days) do
        create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

      travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 1.day) do
        sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons, created_at: 2.months.ago)
        sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

        assert_predicate sponsorship, :matchable?
      end
    end

    test "false for recurring sponsorship when matching enabled for listing and sponsor allowed after deadline" do
      listing = create(:sponsors_listing, :approved, :matchable, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      sponsor = travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 32.days) do
        create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

      travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE + 1.day) do
        refute_predicate sponsorship, :matchable?
      end
    end

    test "true for one-time sponsorship when matching enabled for listing and sponsor allowed" do
      listing = create(:sponsors_listing, :approved, :matchable, tier_count: 0)
      tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

      sponsor = travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 32.days) do
        create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

      travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 1.day) do
        sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons, created_at: 2.months.ago)
        sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)
        assert_predicate sponsorship, :matchable?
      end
    end

    test "false for one-time sponsorship when matching enabled for listing and sponsor allowed after deadline" do
      listing = create(:sponsors_listing, :approved, :matchable, tier_count: 0)
      tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
      sponsor = travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 32.days) do
        create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

      travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE + 1.day) do
        refute_predicate sponsorship, :matchable?
      end
    end

    test "false for spammy sponsor" do
      listing = create(:sponsors_listing, :approved, :matchable, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      sponsor = travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 32.days) do
        create(:credit_card_user, spammy: true,
          plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

      refute_predicate sponsorship, :matchable?
    end if GitHub.spamminess_check_enabled?

    test "false for new sponsor account" do
      new_user_sponsor = create(:user, :verified, plan_subscription: create(:billing_plan_subscription))
      assert_predicate new_user_sponsor, :sponsorship_match_ineligible_from_age_or_spamminess?

      listing = create(:sponsors_listing, :approved, :matchable)
      sponsorship = create(:sponsorship, sponsor: new_user_sponsor, sponsorable: listing.sponsorable)

      refute_predicate sponsorship, :matchable?
    end

    test "false when matching disabled for listing" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)
      tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      sponsor = travel_to(SponsorsListing::ACCEPTED_WAITLIST_MATCH_DEADLINE - 32.days) do
        create(:credit_card_user, plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons)
      end
      sponsorship = create(:sponsorship, tier: tier, sponsor: sponsor)

      refute_predicate sponsorship, :matchable?
    end
  end

  context "#sponsorable_login" do
    test "returns the login of the sponsorship's sponsorable" do
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_equal @sponsorable.login, sponsorship.sponsorable_login
    end
  end

  context "#sponsor_login" do
    test "returns the login of the sponsorship's sponsor" do
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_equal @sponsor.login, sponsorship.sponsor_login
    end
  end

  context ".sponsor_status_by_sponsor_id" do
    test "returns which of the given sponsor IDs are sponsors of the specified sponsorable" do
      sponsorable = @basic_sponsorship.sponsorable
      active_sponsorship2 = create(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: sponsorable)
      other_sponsorship = create(:sponsorship)
      sponsor_ids = [@basic_sponsorship.sponsor_id, @sponsor.id, inactive_sponsorship.sponsor_id,
        other_sponsorship.sponsor_id]

      result = Sponsorship.sponsor_status_by_sponsor_id(sponsor_ids, sponsorable_id: sponsorable.id)

      assert_instance_of Hash, result
      assert result[@basic_sponsorship.sponsor_id]
      assert result[@sponsor.id]
      refute result[inactive_sponsorship.sponsor_id]
      refute result[other_sponsorship.sponsor_id]
    end
  end

  context ".sponsor_status_by_sponsorable_id" do
    test "returns only given IDs who are sponsors of the given sponsorable" do
      active_sponsorship1 = create(:sponsorship, sponsor: @sponsor)
      active_sponsorship2 = create(:sponsorship, sponsor: @sponsor)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsor: @sponsor)

      result = Sponsorship.sponsor_status_by_sponsorable_id(
        sponsorable_ids: [active_sponsorship1.sponsorable_id, active_sponsorship2.sponsorable_id,
          inactive_sponsorship.sponsorable_id, @basic_sponsorship.sponsorable_id],
        sponsor_id: @sponsor.id
      )

      assert_equal 4, result.size
      assert result[active_sponsorship1.sponsorable_id]
      assert result[active_sponsorship2.sponsorable_id]
      refute result[inactive_sponsorship.sponsorable_id]
      refute result[@basic_sponsorship.sponsorable_id]
    end

    test "says org for whom viewer is a billing manager is sponsoring someone when there's a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admin)

      result = Sponsorship.sponsor_status_by_sponsorable_id(
        sponsorable_ids: [sponsorship.sponsorable_id],
        sponsor_id: org.id,
        viewer: billing_manager,
      )

      assert_equal 1, result.size
      assert result[sponsorship.sponsorable_id]
    end
  end

  context "#manually_invoiced_consecutive_recurrence?" do
    test "returns false for Zuora-based invoiced sponsorship" do
      stub_credit_balance do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        zuora_invoiced_sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @sponsorable)
        refute_predicate zuora_invoiced_sponsorship, :manually_invoiced_consecutive_recurrence?
      end
    end

    test "returns false for non-invoiced sponsorship" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      refute_predicate sponsorship, :manually_invoiced_consecutive_recurrence?
    end

    test "returns false for manually invoiced sponsorship that has no immediately preceding similar transfer" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      sponsorship = transfer.sponsorship
      refute_predicate sponsorship, :manually_invoiced_consecutive_recurrence?
    end

    test "returns true for manually invoiced sponsorship that has an immediately preceding similar transfer" do
      transfer1 = travel_to("2022-04-01") { create(:invoiced_sponsorship_transfer, :completed) }
      transfer2 = travel_to("2022-05-01") do
        create(:invoiced_sponsorship_transfer, :completed, sponsor: transfer1.sponsor,
          sponsors_listing: transfer1.sponsors_listing)
      end
      sponsorship = transfer2.sponsorship
      assert_predicate sponsorship, :manually_invoiced_consecutive_recurrence?
    end

    test "returns false for manually invoiced sponsorship that has a preceding similar transfer with a time gap" do
      transfer1 = travel_to("2022-04-01") { create(:invoiced_sponsorship_transfer, :completed) }
      transfer2 = travel_to("2022-06-01") do
        create(:invoiced_sponsorship_transfer, :completed, sponsor: transfer1.sponsor,
          sponsors_listing: transfer1.sponsors_listing)
      end
      sponsorship = transfer2.sponsorship
      refute_predicate sponsorship, :manually_invoiced_consecutive_recurrence?
    end
  end

  context "#update_subscription_item" do
    test "overrides current sponsorship data" do
      current_sub_item = @basic_sponsorship.subscription_item
      current_sub_item.update!(quantity: 0)

      new_tier = create(:sponsors_tier, :published, sponsors_listing: @basic_sponsorship.sponsors_listing)
      new_sub_item = create(:sponsors_subscription_item, account: @basic_sponsorship.sponsor, subscribable: new_tier)

      freeze_time do
        @basic_sponsorship.update_subscription_item(new_sub_item)

        assert_predicate @basic_sponsorship, :active?
        assert_equal new_tier, @basic_sponsorship.tier
        assert_equal new_sub_item, @basic_sponsorship.subscription_item
        assert_equal Time.now, @basic_sponsorship.subscribable_selected_at
      end
    end

    test "ignores cancellation if sub item mismatch" do
      sponsorship = create(:sponsorship, :from_org)
      sponsor = sponsorship.sponsor
      current_sub_item = sponsorship.subscription_item
      current_sub_item.update!(quantity: 0)

      new_tier = create(:sponsors_tier, :published, sponsors_listing: sponsorship.sponsors_listing)
      new_sub_item = create(:sponsors_subscription_item, :cancelled,
        account: sponsorship.sponsor,
        subscribable: new_tier
      )

      sponsorship.update_subscription_item(new_sub_item)

      assert_predicate sponsorship, :active?
      assert_equal current_sub_item.subscribable, sponsorship.tier
      assert_equal current_sub_item, sponsorship.subscription_item
    end
  end

  context "#days_remaining_till_expiration" do
    test "returns nil for recurring sponsorship" do
      sponsorship = create(:sponsorship, tier: @recurring_tier,
        sponsor: @sponsor, sponsorable: @sponsorable)
      assert_nil sponsorship.days_remaining_till_expiration
    end

    test "returns max number of days for a sponsorship started that day" do
      travel_to("2021-01-29") do
        sponsorship = create(:sponsorship, tier: @one_time_tier,
          sponsor: @sponsor, sponsorable: @sponsorable)
        assert_equal Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS,
          sponsorship.days_remaining_till_expiration
      end
    end

    test "returns 0 when the full 30 days have elapsed" do
      max_days = Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS
      now = Time.parse("2021-01-29")
      sponsorship = travel_to((now - max_days.days).beginning_of_day) do
        create(:sponsorship, tier: @one_time_tier,
          sponsor: @sponsor, sponsorable: @sponsorable)
      end
      travel_to(now) do
        assert_equal 0, sponsorship.days_remaining_till_expiration
      end
    end

    test "returns days remaining till we stop showing the user as a sponsor of that maintainer" do
      max_days = Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS
      halfway_through = max_days / 2
      now = Time.parse("2021-01-29")
      sponsorship = travel_to((now - halfway_through.days).beginning_of_day) do
        create(:sponsorship, tier: @one_time_tier,
          sponsor: @sponsor, sponsorable: @sponsorable)
      end
      travel_to(now) do
        assert_equal halfway_through, sponsorship.days_remaining_till_expiration
      end
    end

    test "returns negative number of days if the sponsorship is already expired" do
      sponsorship = create(:sponsorship, tier: @one_time_tier, expires_at: 1.day.ago,
        sponsor: @sponsor, sponsorable: @sponsorable)
      assert_equal -1, sponsorship.days_remaining_till_expiration
    end

    test "returns the number of days left for an invoiced sponsorship" do
      travel_to(Date.current.beginning_of_day) do
        sponsorship = create(:sponsorship, :invoiced, expires_at: 365.days.from_now)
        assert_equal 365, sponsorship.days_remaining_till_expiration
      end
    end

    test "returns 1 for an invoiced sponsorship that expires tomorrow" do
      travel_to(Date.current.beginning_of_day) do
        sponsorship = create(:sponsorship, :invoiced, expires_at: 1.day.from_now)
        assert_equal 1, sponsorship.days_remaining_till_expiration
      end
    end

    test "returns 0 on the day an invoiced sponsorship expires" do
      travel_to(Date.current.beginning_of_day) do
        sponsorship = create(:sponsorship, :invoiced, expires_at: Date.current)
        assert_equal 0, sponsorship.days_remaining_till_expiration
      end
    end

    test "returns a negative number for an expired invoiced sponsorship" do
      travel_to(Date.current.beginning_of_day) do
        sponsorship = create(:sponsorship, :invoiced, expires_at: 1.day.ago)
        assert_equal -1, sponsorship.days_remaining_till_expiration
      end
    end
  end

  context "#readable_by?" do
    test "returns true for everyone for active sponsorship for approved Sponsors listing" do
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      assert sponsorship.readable_by?(@sponsor)
      assert sponsorship.readable_by?(@sponsorable)
      assert sponsorship.readable_by?(nil)
      assert sponsorship.readable_by?(@rando)
    end

    test "returns false when Sponsors listing is not approved unless viewer is the sponsor" do
      sponsorable = create(:user, :verified)
      create(:sponsors_listing, :disabled, sponsorable: sponsorable)
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable)

      assert sponsorship.readable_by?(@sponsor)
      refute sponsorship.readable_by?(sponsorable)
      refute sponsorship.readable_by?(nil)
      refute sponsorship.readable_by?(@rando)
    end

    test "returns false when sponsorship is inactive unless viewer is the sponsor" do
      sponsorship = build(:sponsorship, :inactive, sponsor: @sponsor, sponsorable: @sponsorable)

      assert sponsorship.readable_by?(@sponsor)
      refute sponsorship.readable_by?(@sponsorable)
      refute sponsorship.readable_by?(nil)
      refute sponsorship.readable_by?(@rando)
    end
  end

  context "#publicly_visible?" do
    test "returns true for active sponsorship for approved Sponsors listing" do
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_predicate sponsorship, :publicly_visible?
    end

    test "returns false for active sponsorship for non-approved Sponsors listing" do
      sponsorable = create(:user, :verified)
      create(:sponsors_listing, :pending_approval, sponsorable: sponsorable)
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable)
      refute_predicate sponsorship, :publicly_visible?
    end

    test "returns false for inactive sponsorship for approved Sponsors listing" do
      sponsorship = build(:sponsorship, :inactive, sponsor: @sponsor, sponsorable: @sponsorable)
      refute_predicate sponsorship, :publicly_visible?
    end

    test "returns false when Sponsors listing does not exist" do
      sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      @listing.delete
      refute_predicate sponsorship, :publicly_visible?
    end
  end

  def assert_amount_readable_by(sponsorship, viewer:)
    viewer_desc = viewer || "anonymous viewer"
    assert sponsorship.amount_readable_by?(viewer), "expected #amount_readable_by? to be true for #{viewer_desc}"
    assert sponsorship.async_amount_readable_by?(viewer).sync,
      "expected #async_amount_readable_by? to be true for #{viewer_desc}"
    assert_equal [sponsorship], Sponsorship.amount_visible_to(viewer).where(id: sponsorship),
      "expected .amount_visible_to scope to include sponsorship for #{viewer_desc}"
  end

  def refute_amount_readable_by(sponsorship, viewer:)
    viewer_desc = viewer || "anonymous viewer"
    refute sponsorship.amount_readable_by?(viewer), "expected #amount_readable_by? to be false for #{viewer_desc}"
    refute sponsorship.async_amount_readable_by?(viewer).sync,
      "expected #async_amount_readable_by? to be false for #{viewer_desc}"
    assert_empty Sponsorship.amount_visible_to(viewer).where(id: sponsorship),
      "expected .amount_visible_to scope to omit sponsorship for #{viewer_desc}"
  end

  context "#amount_readable_by? and #async_amount_readable_by? and .amount_visible_to scope" do
    test "true for sponsorship from org for org admin viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      assert_amount_readable_by(sponsorship, viewer: org.admins.first)
    end

    test "true for sponsorship from org for billing manager viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      assert_amount_readable_by(sponsorship, viewer: billing_manager)
    end

    test "true for sponsorship from org for admin viewer of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)

      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      assert_amount_readable_by(sponsorship, viewer: org_that_gets_credit.admins.first)
    end

    test "true for sponsorship from org for billing manager viewer of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)
      org_that_gets_credit_billing_manager = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_manager,
        actor: org_that_gets_credit.admins.first)

      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      assert_amount_readable_by(sponsorship, viewer: org_that_gets_credit_billing_manager)
    end

    test "true for sponsorship to org for org admin viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable
      assert_amount_readable_by(sponsorship, viewer: org.admins.first)
    end

    test "false for sponsorship to org for org billing manager viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      refute_amount_readable_by(sponsorship, viewer: billing_manager)
    end

    test "false for sponsorship from org for org member viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      refute_amount_readable_by(sponsorship, viewer: org_member)
    end

    test "false for sponsorship from org for viewer who is a member of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)
      org_member = create(:user)
      org_that_gets_credit.add_member(org_member)

      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      refute_amount_readable_by(sponsorship, viewer: org_member)
    end

    test "false for sponsorship to org for org member viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable
      org_member = create(:user)
      org.add_member(org_member)

      refute_amount_readable_by(sponsorship, viewer: org_member)
    end

    test "false for sponsorship from org for non-org member viewer" do
      sponsorship = create(:sponsorship, :from_org)

      refute_amount_readable_by(sponsorship, viewer: @rando)
    end

    test "false for sponsorship to org for non-org member viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable

      refute_amount_readable_by(sponsorship, viewer: @rando)
    end

    test "false for sponsorship to org for anonymous viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      refute_amount_readable_by(sponsorship, viewer: nil)
    end

    test "false for sponsorship to user for anonymous viewer" do
      refute_amount_readable_by(@basic_sponsorship, viewer: nil)
    end

    test "true for sponsorship for its sponsor" do
      assert_amount_readable_by(@basic_sponsorship, viewer: @basic_sponsorship.sponsor)
    end

    test "true for sponsorship for its sponsored maintainer" do
      assert_amount_readable_by(@basic_sponsorship, viewer: @basic_sponsorship.sponsorable)
    end

    test "false for sponsorship to user for a viewer who is not involved" do
      refute_amount_readable_by(@basic_sponsorship, viewer: @rando)
    end
  end

  context "#adminable_by?" do
    test "true for sponsorship from org for org admin viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      assert sponsorship.adminable_by?(org.admins.first)
    end

    test "true for staff viewer for an invoiced org's sponsorship" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
      sponsorship = create(:sponsorship, sponsor: invoiced_org)
      assert sponsorship.adminable_by?(@staff)
    end

    test "false for staff viewer for a non-invoiced org's sponsorship" do
      sponsorship = create(:sponsorship, :from_org)
      refute sponsorship.adminable_by?(@staff)
    end

    test "true for sponsorship from org for billing manager viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      assert sponsorship.adminable_by?(billing_manager)
    end

    test "true for sponsorship from org for admin viewer of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)

      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      assert sponsorship.adminable_by?(org_that_gets_credit.admins.first)
    end

    test "true for sponsorship from org for billing manager viewer of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      org_that_gets_credit_billing_manager = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_manager,
        actor: org_that_gets_credit.admins.first)

      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      assert sponsorship.adminable_by?(org_that_gets_credit_billing_manager)
    end

    test "false for sponsorship to org for org admin viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      recipient_org = sponsorship.sponsorable
      refute sponsorship.adminable_by?(recipient_org.admins.first)
    end

    test "false for sponsorship to org for org billing manager viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable
      recipient_billing_manager = create(:user)
      org.billing.add_manager(recipient_billing_manager, actor: org.admins.first)
      refute sponsorship.adminable_by?(recipient_billing_manager)
    end

    test "false for sponsorship from org for org member viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      refute sponsorship.adminable_by?(org_member)
    end

    test "false for sponsorship from org for viewer who is a member of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)
      org_member = create(:user)
      org_that_gets_credit.add_member(org_member)

      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      refute sponsorship.adminable_by?(org_member)
    end

    test "false for sponsorship to org for org member viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable
      org_member = create(:user)
      org.add_member(org_member)

      refute sponsorship.adminable_by?(org_member)
    end

    test "false for sponsorship from org for non-org member viewer" do
      sponsorship = create(:sponsorship, :from_org)

      refute sponsorship.adminable_by?(@rando)
    end

    test "false for sponsorship to org for non-org member viewer" do
      sponsorship = create(:sponsorship, :with_org_sponsorable)
      org = sponsorship.sponsorable

      refute sponsorship.adminable_by?(@rando)
    end

    test "false for anonymous viewer" do
      refute @basic_sponsorship.adminable_by?(nil)
    end

    test "true for sponsorship for its sponsor" do
      assert @basic_sponsorship.adminable_by?(@basic_sponsorship.sponsor)
    end

    test "false for sponsorship for its sponsored maintainer" do
      refute @basic_sponsorship.adminable_by?(@basic_sponsorship.sponsorable)
    end

    test "false for sponsorship to user for a viewer who is not involved" do
      refute @basic_sponsorship.adminable_by?(@rando)
    end
  end

  def assert_sponsor_readable_by(sponsorship, viewer:)
    viewer_desc = viewer || "anonymous viewer"
    assert sponsorship.sponsor_readable_by?(viewer), "expected #sponsor_readable_by? to be true for #{viewer_desc}"
    assert sponsorship.async_sponsor_readable_by?(viewer).sync,
      "expected #async_sponsor_readable_by? to be true for #{viewer_desc}"
    assert_equal [sponsorship], Sponsorship.sponsor_visible_to(viewer).where(id: sponsorship.id),
      "expected .sponsor_visible_to scope to include sponsorship for #{viewer_desc}"
  end

  def refute_sponsor_readable_by(sponsorship, viewer:)
    viewer_desc = viewer || "anonymous viewer"
    refute sponsorship.sponsor_readable_by?(viewer), "expected #sponsor_readable_by? to be false for #{viewer_desc}"
    refute sponsorship.async_sponsor_readable_by?(viewer).sync,
      "expected #async_sponsor_readable_by? to be false for #{viewer_desc}"
    refute_equal [sponsorship], Sponsorship.sponsor_visible_to(viewer).where(id: sponsorship.id),
      "expected .sponsor_visible_to scope to omit sponsorship for #{viewer_desc}"
  end

  context "#sponsor_readable_by? and #async_sponsor_readable_by? and .sponsor_visible_to scope" do
    test "true for public sponsorship" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      assert_predicate sponsorship, :privacy_public?
      assert_sponsor_readable_by(sponsorship, viewer: nil)
    end

    test "true for the sponsor of a private sponsorship" do
      sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, sponsor: @sponsor)
      assert_sponsor_readable_by(sponsorship, viewer: @sponsor)
    end

    test "true for the recipient of a private sponsorship" do
      sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, sponsor: @sponsor)
      assert_sponsor_readable_by(sponsorship, viewer: @sponsorable)
    end

    test "false for staff for a private sponsorship when they don't otherwise have access", skip_enterprise: true do
      staff = create(:biztools_user)
      sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, sponsor: @sponsor)
      refute_sponsor_readable_by(sponsorship, viewer: staff)
    end

    test "true for org admin for private org sponsorship" do
      org_admin = create(:user)
      org = create(:organization, :sponsorable, admin: org_admin)
      sponsorship = create(:sponsorship, :private, sponsorable: org, sponsor: @sponsor)
      assert_sponsor_readable_by(sponsorship, viewer: org_admin)
    end

    test "true for org admin for private org sponsorship using a custom tier made by a different user" do
      org_admin = create(:user)
      billing_manager = create(:user)

      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: org_admin)
      org.billing.add_manager(billing_manager, actor: org_admin)

      custom_tier = create(:sponsors_tier, :custom, creator: billing_manager, sponsors_listing: @listing)

      sponsorship = create(:sponsorship, :private, sponsor: org, tier: custom_tier, sponsorable: @sponsorable)
      assert_sponsor_readable_by(sponsorship, viewer: org_admin)
    end

    test "true for billing manager for private org sponsorship using a custom tier made by a different user" do
      org_admin = create(:user)
      billing_manager = create(:user)

      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: org_admin)
      org.billing.add_manager(billing_manager, actor: org_admin)

      custom_tier = create(:sponsors_tier, :custom, creator: org_admin, sponsors_listing: @listing)

      sponsorship = create(:sponsorship, :private, sponsor: org, tier: custom_tier, sponsorable: @sponsorable)
      assert_sponsor_readable_by(sponsorship, viewer: billing_manager)
    end

    test "true for private sponsorship from org for admin viewer of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)

      sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)
      assert_sponsor_readable_by(sponsorship, viewer: org_that_gets_credit.admins.first)
    end

    test "true for private sponsorship from org for billing manager viewer of linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit,
        sponsoring_linked_organization: org_that_pays)
      org_that_gets_credit_billing_manager = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_manager,
        actor: org_that_gets_credit.admins.first)

      sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)
      assert_sponsor_readable_by(sponsorship, viewer: org_that_gets_credit_billing_manager)
    end

    test "false for anonymous viewer for a private sponsorship" do
      sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, sponsor: @sponsor)
      refute_sponsor_readable_by(sponsorship, viewer: nil)
    end

    test "false for unrelated viewer for a private sponsorship" do
      sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, sponsor: @sponsor)
      refute_sponsor_readable_by(sponsorship, viewer: @rando)
    end

    test "false for billing manager when org is receiving a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)
      refute_sponsor_readable_by(sponsorship, viewer: billing_manager)
    end

    test "true for org admin when org is receiving a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      assert_sponsor_readable_by(sponsorship, viewer: org.admins.first)
    end

    test "true for org member when org is receiving a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :with_org_sponsorable)
      org = sponsorship.sponsorable
      org_member = create(:user)
      org.add_member(org_member)
      assert_sponsor_readable_by(sponsorship, viewer: org_member)
    end
  end

  context "#async_linked_or_direct_sponsor_billing_manageable_by" do
    test "returns true when viewer is the sponsor" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

      assert sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@sponsor).sync
    end

    test "returns true when viewer is admin of sponsor org" do
      sponsor = create(:organization)
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: sponsor)
      admin = sponsor.admins.first

      assert sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(admin).sync
    end

    test "returns true when viewer is billing manager of sponsor org" do
      sponsor = create(:organization)
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: sponsor)
      sponsor.billing.add_manager(@rando, actor: sponsor.admins.first)

      assert sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns true when viewer is member of sponsor org" do
      sponsor = create(:organization)
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: sponsor)
      sponsor.add_member(@rando)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns true when viewer is admin of linked org" do
      linked_org = create(:organization)
      admin = linked_org.admins.first
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      create(:organization_profile, organization: linked_org, sponsoring_linked_organization: sponsorship.sponsor)

      assert sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(admin).sync
    end

    test "returns true when viewer is billing manager of linked org" do
      linked_org = create(:organization)
      linked_org.billing.add_manager(@rando, actor: linked_org.admins.first)
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      create(:organization_profile, organization: linked_org, sponsoring_linked_organization: sponsorship.sponsor)

      assert sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns false when viewer is member of linked org" do
      linked_org = create(:organization)
      linked_org.add_member(@rando)
      sponsorship = create(:sponsorship, :from_org, sponsorable: @sponsorable)
      create(:organization_profile, organization: linked_org, sponsoring_linked_organization: sponsorship.sponsor)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns false when viewer is the sponsorable" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@sponsorable).sync
    end

    test "returns false when viewer is admin of sponsorable org" do
      sponsorable = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, sponsorable: sponsorable, sponsor: @sponsor)
      admin = sponsorable.admins.first

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(admin).sync
    end

    test "returns false when viewer is billing manager of sponsorable org" do
      sponsorable = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, sponsorable: sponsorable, sponsor: @sponsor)
      sponsorable.billing.add_manager(@rando, actor: sponsorable.admins.first)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns false when viewer is member of sponsorable org" do
      sponsorable = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, sponsorable: sponsorable, sponsor: @sponsor)
      sponsorable.add_member(@rando)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns false when viewer is random user" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(@rando).sync
    end

    test "returns false when viewer is anonymous viewer" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(nil).sync
    end

    test "returns false when sponsor is deleted" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      sponsorship.update(sponsor: nil)

      refute sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(nil).sync
    end
  end

  context "#sponsors_invoiced?" do
    test "true for invoiced org with active sponsorship-specific Zuora account", skip_enterprise: true do
      stub_credit_balance(20_000_00) do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        refute_nil invoiced_org.sponsors_customer

        sponsorship = create(:sponsorship, sponsor: invoiced_org)

        assert_predicate sponsorship, :sponsors_invoiced?
      end
    end

    # https://github.com/github/sponsors/issues/5468
    test "false when sponsor no longer exists" do
      @basic_sponsorship.sponsor.delete

      refute_predicate @basic_sponsorship.reload, :sponsors_invoiced?
    end

    test "false for sponsorship with a user sponsor" do
      sponsor = @basic_sponsorship.sponsor
      assert_predicate sponsor, :user?, "Sponsor must be a user"

      refute_predicate @basic_sponsorship, :sponsors_invoiced?
    end

    test "false when the org doesn't have a sponsorship-specific Zuora account" do
      stub_credit_balance do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        invoiced_org.sponsors_customer.delete
        assert_nil invoiced_org.reload.sponsors_customer

        sponsorship = create(:sponsorship, sponsor: invoiced_org)

        refute_predicate sponsorship, :sponsors_invoiced?
      end
    end

    test "can be preloaded to avoid N+1s" do
      stub_credit_balance(20_000_00) do
        invoiced_sponsorship1, invoiced_sponsorship2 = create_pair(:sponsorship, :sponsors_invoiced)

        GitHub::PrefillAssociations.prefill_batch_method(
          [@basic_sponsorship, invoiced_sponsorship1, invoiced_sponsorship2],
          :sponsors_invoiced?
        )

        assert_query_count 0 do
          refute_predicate @basic_sponsorship, :sponsors_invoiced?
          assert_predicate invoiced_sponsorship1, :sponsors_invoiced?
          assert_predicate invoiced_sponsorship2, :sponsors_invoiced?
        end
      end
    end

    test "false when billing is disabled" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)

      sponsorship = create(:sponsorship, sponsor: invoiced_org)
      refute_predicate sponsorship, :sponsors_invoiced?
    end unless GitHub.billing_enabled?

    test "false when Sponsors is disabled" do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)

      sponsorship = create(:sponsorship, sponsor: invoiced_org)

      refute_predicate sponsorship, :sponsors_invoiced?
    end unless GitHub.sponsors_enabled?
  end

  context "sponsorable metadata" do
    test "limits how many metadata entries there can be" do
      sanitized_sponsorable_metadata = { "a" => "b" }
      raw_sponsorable_metadata = { "metadata_a" => "b" }

      (1..SponsorsListing::SponsorableMetadata::MAX_METADATA_PAIRS).each do |i|
        sanitized_sponsorable_metadata["a" + i.to_s] = "b" unless i == SponsorsListing::SponsorableMetadata::MAX_METADATA_PAIRS
        raw_sponsorable_metadata["metadata_a" + i.to_s] = "b"
      end

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "truncates metadata key length" do
      sanitized_sponsorable_metadata = { "a" * SponsorsListing::SponsorableMetadata::MAX_METADATA_KEY_LENGTH => "b" }
      raw_sponsorable_metadata = { "metadata_a" + ("a" * (SponsorsListing::SponsorableMetadata::MAX_METADATA_KEY_LENGTH + 1)) => "b" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "truncates metadata value length" do
      sanitized_sponsorable_metadata = { "a" => "b" * SponsorsListing::SponsorableMetadata::MAX_METADATA_VALUE_LENGTH }
      raw_sponsorable_metadata = { "metadata_a" => "b" * (SponsorsListing::SponsorableMetadata::MAX_METADATA_VALUE_LENGTH + 1) }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "removes whitespaces in keys" do
      sanitized_sponsorable_metadata = { "hello" => "a" }
      raw_sponsorable_metadata = { "metadata_ hel lo " => "a" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "removes whitespaces in values" do
      sanitized_sponsorable_metadata = { "hello" => "aa" }
      raw_sponsorable_metadata = { "metadata_hello" => "a a " }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "strips HTML from metadata keys" do
      sanitized_sponsorable_metadata = { "hellohacktoberfest" => "a" }
      raw_sponsorable_metadata = { "metadata_<p>hello hacktoberfest</p>" => "a" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "strips HTML from metadata values" do
      sanitized_sponsorable_metadata = { "a" => "hellohacktoberfest" }
      raw_sponsorable_metadata = { "metadata_a" => "<p>hello hacktoberfest</p>" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "strips JavaScript from metadata keys" do
      raw_sponsorable_metadata = { "metadata_<script>alert('test');</script>" => "a" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_nil sponsorship.latest_sponsorable_metadata
    end

    test "strips JavaScript from metadata values" do
      raw_sponsorable_metadata = { "metadata_a" => "<script>alert('test');</script>" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_nil sponsorship.latest_sponsorable_metadata
    end

    test "strips non-alphanumeric characters from metadata keys" do
      sanitized_sponsorable_metadata = { "hello" => "a" }
      raw_sponsorable_metadata = { "metadata_.h#e*l)l=o+" => "a" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "removes pairs with empty keys" do
      sanitized_sponsorable_metadata = { "a" => "b" }
      raw_sponsorable_metadata = { "metadata_a" => "b", "" => "a" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "removes pairs with empty values" do
      sanitized_sponsorable_metadata = { "a" => "b" }
      raw_sponsorable_metadata = { "metadata_a" => "b", "metadata_b" => "" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "removes pairs with duplicated keys" do
      sanitized_sponsorable_metadata = { "a" => "c" }
      # After sanitization, key "metadata_a!" becomes "metadata_a"
      raw_sponsorable_metadata = { "metadata_a" => "b", "metadata_a!" => "c" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "removes pairs whose keys do not have the metadata prefix" do
      sanitized_sponsorable_metadata = { "a" => "b" }
      raw_sponsorable_metadata = { "metadata_a" => "b", "source" => "c" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
    end

    test "latest sponsorable metadata is nil when metadata is empty after sanitization" do
      raw_sponsorable_metadata = { "source" => "c" }

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_nil sponsorship.latest_sponsorable_metadata
    end

    test "latest sponsorable metadata is nil when metadata is nil" do
      raw_sponsorable_metadata = nil

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_nil sponsorship.latest_sponsorable_metadata
    end

    test "latest sponsorable metadata is nil when metadata is empty" do
      raw_sponsorable_metadata = {}

      sponsorship = create(:sponsorship, sponsor: @sponsor,
        sponsorable: @sponsorable, tier: @recurring_tier, latest_sponsorable_metadata: raw_sponsorable_metadata)

      assert_nil sponsorship.latest_sponsorable_metadata
    end

    test "removes keys with blocked substrings anywhere in them" do
      blocked_substring = "road"
      Sponsors::ProfaneLanguageCheck.stub_const(:BLOCKED_TERMS, [blocked_substring]) do
        sanitized_sponsorable_metadata = { "a" => "b" }
        raw_sponsorable_metadata = { "metadata_a" => "b", "metadata_asdf#{blocked_substring}asdf" => "c" }

        sponsorship = build(:sponsorship, latest_sponsorable_metadata: raw_sponsorable_metadata)
        sponsorship.validate

        assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
      end
    end

    test "removes values with blocked substrings anywhere in them" do
      blocked_substring = "road"
      Sponsors::ProfaneLanguageCheck.stub_const(:BLOCKED_TERMS, [blocked_substring]) do
        sanitized_sponsorable_metadata = { "a" => "b" }
        raw_sponsorable_metadata = { "metadata_a" => "b", "metadata_b" => "random#{blocked_substring}random" }

        sponsorship = build(:sponsorship, latest_sponsorable_metadata: raw_sponsorable_metadata)
        sponsorship.validate

        assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
      end
    end

    test "removes keys with blocked substrings regardless of casing" do
      blocked_substring = "road"
      Sponsors::ProfaneLanguageCheck.stub_const(:BLOCKED_TERMS, [blocked_substring]) do
        sanitized_sponsorable_metadata = { "a" => "b" }
        raw_sponsorable_metadata = { "metadata_a" => "b", "metadata_asdf#{blocked_substring.upcase}asdf" => "c" }

        sponsorship = build(:sponsorship, latest_sponsorable_metadata: raw_sponsorable_metadata)
        sponsorship.validate

        assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
      end
    end

    test "removes values with blocked substrings regardless of casing" do
      blocked_substring = "road"
      Sponsors::ProfaneLanguageCheck.stub_const(:BLOCKED_TERMS, [blocked_substring]) do
        sanitized_sponsorable_metadata = { "a" => "b" }
        raw_sponsorable_metadata = { "metadata_a" => "b", "metadata_b" => "random#{blocked_substring.upcase}random" }

        sponsorship = build(:sponsorship, latest_sponsorable_metadata: raw_sponsorable_metadata)
        sponsorship.validate

        assert_equal sanitized_sponsorable_metadata, sponsorship.latest_sponsorable_metadata
      end
    end
  end

  test "disallows some changes when locked" do
    locked_sponsorship = create(:sponsorship, sponsor: @sponsor,
      sponsorable: @sponsorable, tier: @one_time_tier)
    assert_predicate locked_sponsorship, :locked?

    locked_sponsorship.tier = create(:sponsors_tier, :published, :one_time,
      sponsors_listing: @listing)
    locked_sponsorship.skip_proration = !locked_sponsorship.skip_proration
    locked_sponsorship.sponsor = create(:user)
    locked_sponsorship.sponsorable = create(:organization)
    locked_sponsorship.subscribable_selected_at = 1.week.ago
    locked_sponsorship.subscription_item = create(:billing_subscription_item)

    refute_predicate locked_sponsorship, :valid?
    assert_includes locked_sponsorship.errors[:subscribable_id],
      "cannot be changed when sponsorship is locked"
    assert_includes locked_sponsorship.errors[:skip_proration],
      "cannot be changed when sponsorship is locked"
    assert_includes locked_sponsorship.errors[:sponsor_id],
      "cannot be changed when sponsorship is locked"
    assert_includes locked_sponsorship.errors[:sponsorable_id],
      "cannot be changed when sponsorship is locked"
    assert_includes locked_sponsorship.errors[:subscribable_selected_at],
      "cannot be changed when sponsorship is locked"
    assert_includes locked_sponsorship.errors[:subscription_item_id],
      "cannot be changed when sponsorship is locked"
  end

  test "disallows a sponsor to have a recurring and a one-time sponsorship for the same maintainer" do
    create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    sub_item = build(:sponsors_subscription_item, plan_subscription: @sponsor.plan_subscription,
      subscribable: @one_time_tier)

    sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
      tier: @one_time_tier, subscription_item: sub_item)

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:sponsor_id], "has already been taken"
  end

  test "disallows a sponsor to have multiple one-time sponsorships for the same maintainer" do
    create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
      tier: @one_time_tier)
    other_one_time_tier = create(:sponsors_tier, :published, :one_time,
      sponsors_listing: @listing)
    sub_item = build(:sponsors_subscription_item, plan_subscription: @sponsor.plan_subscription,
      subscribable: other_one_time_tier)

    sponsorship = build(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
      tier: other_one_time_tier, subscription_item: sub_item)

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:sponsor_id], "has already been taken"
  end

  test "disallows having a Sponsors tier for a different listing than the sponsorable" do
    tier = create(:sponsors_tier, :published)
    sponsorable = create(:user, :sponsorable)

    sponsorship = Sponsorship.new(tier: tier, sponsorable: sponsorable)

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:subscribable_id], "is not @#{sponsorable}'s"
  end

  test "disallows reusing a custom tier for multiple sponsorships" do
    custom_tier = create(:sponsors_tier, :approved_sponsors_listing, :custom)
    create(:sponsorship, tier: custom_tier, sponsor: custom_tier.creator,
      sponsorable: custom_tier.sponsorable)
    sponsorship = build(:sponsorship, tier: custom_tier, sponsor: custom_tier.creator,
      sponsorable: custom_tier.sponsorable)

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:tier], "has already been used for a sponsorship"
  end

  test "disallows reusing an invoiced tier for multiple sponsorships" do
    existing_sponsorship = create(:sponsorship, :invoiced)
    dup_sponsorship = build(:sponsorship, :invoiced, tier: existing_sponsorship.tier)

    assert_predicate existing_sponsorship, :valid?
    refute_predicate dup_sponsorship, :valid?
    assert_includes dup_sponsorship.errors[:tier], "has already been used for a sponsorship"
  end

  test "disallows sponsoring yourself" do
    self_sponsorship = build(:sponsorship, tier: @recurring_tier, sponsor: @sponsorable, sponsors_listing: @listing)

    refute_predicate self_sponsorship, :valid?
    assert_includes self_sponsorship.errors[:sponsor], "cannot sponsor themselves"
  end

  test "cannot be created if sponsor has blocked sponsorable" do
    @sponsor.block(@sponsorable)
    assert_raises ActiveRecord::RecordInvalid do
      create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
    end
  end

  test "cannot be created if sponsorable has blocked sponsor" do
    @sponsorable.block(@sponsor)
    assert_raises ActiveRecord::RecordInvalid do
      create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
    end
  end

  test "cannot be created with an invalid subscription item" do
    assert_raises ActiveRecord::RecordInvalid do
      t = build(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor, subscription_item_id: nil)
      t.save!
    end
  end

  test "requires tier" do
    sponsorship = Sponsorship.new(tier: nil)
    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:tier], "must exist"
  end

  test "requires subscribable_selected_at for new sponsorship" do
    sponsorship = Sponsorship.new(subscribable_selected_at: nil)
    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:subscribable_selected_at], "can't be blank"
  end

  test "does not require subscribable_selected_at for existing sponsorship" do
    @basic_sponsorship.update_attribute(:subscribable_selected_at, nil)
    @basic_sponsorship.reload

    # Change some other field
    @basic_sponsorship.is_sponsor_opted_in_to_email = !@basic_sponsorship.is_sponsor_opted_in_to_email

    assert_predicate @basic_sponsorship, :valid?
  end

  test "does not require a subscription item for invoiced sponsorships" do
    sponsorship = build(:sponsorship, :invoiced)

    refute sponsorship.subscription_item
    assert_predicate sponsorship, :valid?
  end

  test "cannot set a subscription item for an invoiced sponsorship" do
    sponsorship = build(:sponsorship, :invoiced)
    assert_predicate sponsorship, :valid?

    sponsorship.subscription_item = create(:sponsors_subscription_item)

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:subscription_item], "cannot be associated with an invoiced sponsorship"
  end

  test "requires expires_at for invoiced sponsorships" do
    sponsorship = create(:sponsorship, :invoiced, sponsor: @sponsor)

    sponsorship.expires_at = nil

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:expires_at], "can't be blank"
  end

  test "requires expires_at for one-time sponsorships" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
      tier: @one_time_tier)
    refute_nil sponsorship.expires_at, "should have been set automatically"

    sponsorship.update_attribute(:expires_at, nil)

    refute_predicate sponsorship, :valid?
    assert_includes sponsorship.errors[:expires_at], "can't be blank"
  end

  test "does not require expires_at for recurring sponsorships" do
    sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor,
      tier: @recurring_tier)
    assert_nil sponsorship.expires_at
    assert_predicate sponsorship, :valid?
  end

  test "destroys the sponsorship record when the sponsor is destroyed" do
    sponsorable = create(:user, :sponsorable)
    sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
    create(:sponsorship, sponsorable: sponsorable, sponsor: sponsor)

    assert_equal 1, sponsorable.sponsorships_as_sponsorable.count

    assert_difference(-> { Sponsorship.count }, -1) do
      sponsor.destroy
    end

    sponsorable.reload
    assert_equal 0, sponsorable.sponsorships_as_sponsorable.count
  end

  test "destroys the sponsorship record when the payment source is Patreon and the sponsor is destroyed" do
    sponsorable = create(:user, :sponsorable)
    sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
    create(:sponsorship, :patreon, sponsorable: sponsorable, sponsor: sponsor)

    assert_equal 1, sponsorable.sponsorships_as_sponsorable.count

    assert_difference(-> { Sponsorship.count }, -1) do
      sponsor.destroy
    end

    sponsorable.reload
    assert_equal 0, sponsorable.sponsorships_as_sponsorable.count
  end

  test "one-time payments are locked at creation" do
    sponsorship = create(:sponsorship, tier: @one_time_tier,
      sponsor: @sponsor, sponsorable: @sponsorable)
    assert_predicate sponsorship, :locked?
  end

  test "recurring payments are not locked at creation" do
    sponsorship = create(:sponsorship, tier: @recurring_tier,
      sponsor: @sponsor, sponsorable: @sponsorable)
    refute_predicate sponsorship, :locked?
  end

  context "#one_time_payment?" do
    test "true when using a one-time tier" do
      sponsorship = Sponsorship.new(tier: @one_time_tier)
      assert_predicate sponsorship, :one_time_payment?
    end

    test "false when using a recurring tier" do
      sponsorship = Sponsorship.new(tier: @recurring_tier)
      refute_predicate sponsorship, :one_time_payment?
    end
  end

  context "#recurring_or_invoiced_payment?" do
    test "false when using a one-time, non-invoiced tier" do
      sponsorship = Sponsorship.new(tier: @one_time_tier)
      refute_predicate sponsorship, :recurring_or_invoiced_payment?
    end

    test "true when using a recurring tier" do
      sponsorship = Sponsorship.new(tier: @recurring_tier)
      assert_predicate sponsorship, :recurring_or_invoiced_payment?
    end

    test "true when there's an invoiced sponsorship transfer" do
      transfer = create(:invoiced_sponsorship_transfer)
      invoiced_tier = create(:sponsors_tier, :invoiced, sponsors_listing: transfer.sponsors_listing)
      sponsorship = Sponsorship.new(tier: invoiced_tier, invoiced_sponsorship_transfer: transfer)
      assert_predicate sponsorship, :recurring_or_invoiced_payment?
    end
  end

  context "#recurring_payment?" do
    test "false when using a one-time tier" do
      sponsorship = Sponsorship.new(tier: @one_time_tier)
      refute_predicate sponsorship, :recurring_payment?
    end

    test "true when using a recurring tier" do
      sponsorship = Sponsorship.new(tier: @recurring_tier)
      assert_predicate sponsorship, :recurring_payment?
    end
  end

  context "#first_time_sponsor?" do
    test "true when it's the user's only sponsorship where they're the sponsor" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      assert_predicate sponsorship, :first_time_sponsor?
    end

    test "false when it's not the user's only sponsorship where they're the sponsor" do
      sponsorship1 = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      sponsorship2 = create(:sponsorship, sponsor: @sponsor)
      refute_predicate sponsorship2, :first_time_sponsor?
    end

    test "false when the user is reactivating an inactive sponsorship" do
      sponsorship = travel_to(6.months.ago) do
        create(:sponsorship, :inactive, sponsor: @sponsor, sponsorable: @sponsorable,
          tier: @recurring_tier)
      end
      sponsorship.active = true
      refute_predicate sponsorship, :first_time_sponsor?
    end
  end

  context "#first_time_sponsorable?" do
    test "true when it's the user's only sponsorship where they're the sponsorable" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier,
        sponsor: @sponsor)
      assert_predicate sponsorship, :first_time_sponsorable?
    end

    test "false when it's not the user's only sponsorship where they're the sponsorable" do
      sponsorship1 = create(:sponsorship, sponsorable: @sponsorable)
      sponsorship2 = create(:sponsorship, sponsorable: @sponsorable)
      refute_predicate sponsorship2, :first_time_sponsorable?
    end

    test "false when the sponsor has reactivated an inactive sponsorship" do
      sponsorship = travel_to(6.months.ago) do
        create(:sponsorship, :inactive, sponsor: @sponsor, sponsorable: @sponsorable,
          tier: @recurring_tier)
      end
      sponsorship.active = true
      refute_predicate sponsorship, :first_time_sponsorable?
    end
  end

  context "#all_active_as_sponsorable" do
    test "filters inactive sponsorships" do
      second_sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
      active_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable, sponsor: second_sponsor)

      invoiced_sponsorship = create(:sponsorship, :invoiced,
        invoiced_sponsorship_transfer: create(
          :invoiced_sponsorship_transfer,
          sponsors_listing: @sponsorable.sponsors_listing,
        ),
      )

      inactive_invoiced_sponsorship = create(:sponsorship, :invoiced, :inactive,
        invoiced_sponsorship_transfer: create(
          :invoiced_sponsorship_transfer,
          sponsors_listing: @sponsorable.sponsors_listing,
        ),
      )

      sponsorships = Sponsorship.all_active_as_sponsorable(sponsorable: @sponsorable)
      assert_includes sponsorships, active_sponsorship
      assert_includes sponsorships, invoiced_sponsorship
      refute_includes sponsorships, inactive_sponsorship
      refute_includes sponsorships, inactive_invoiced_sponsorship
    end

    test "scopes to tier when present" do
      tier = create :sponsors_tier, :published, sponsors_listing: @listing
      other_sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
      first_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor)
      second_sponsorship = create(:sponsorship, tier: tier, sponsorable: @sponsorable,
        sponsor: other_sponsor)

      sponsorships = Sponsorship.all_active_as_sponsorable(sponsorable: @sponsorable)
      assert_same_elements [first_sponsorship, second_sponsorship], sponsorships

      sponsorships = Sponsorship.all_active_as_sponsorable(sponsorable: @sponsorable, tier: first_sponsorship.tier)
      assert_equal [first_sponsorship], sponsorships
    end

    test "scopes to custom tiers at the same price when custom tier is given" do
      custom_tier1 = create(:sponsors_tier, :approved_sponsors_listing, :custom,
        monthly_price_in_cents: 15_00)
      listing = custom_tier1.sponsors_listing
      sponsorship1 = create(:sponsorship, tier: custom_tier1)

      # Same listing, different amount:
      custom_tier2 = create(:sponsors_tier, :custom, sponsors_listing: listing)
      sponsorship2 = create(:sponsorship, tier: custom_tier2)

      # Same listing, same amount:
      custom_tier3 = create(:sponsors_tier, :custom, sponsors_listing: listing,
        monthly_price_in_cents: custom_tier1.monthly_price_in_cents)
      sponsorship3 = create(:sponsorship, tier: custom_tier3)

      # Different listing, same amount:
      custom_tier4 = create(:sponsors_tier, :approved_sponsors_listing, :custom,
        monthly_price_in_cents: custom_tier1.monthly_price_in_cents)
      sponsorship4 = create(:sponsorship, tier: custom_tier4)

      result = Sponsorship.all_active_as_sponsorable(sponsorable: listing.sponsorable,
        tier: custom_tier1)

      assert_includes result, sponsorship1
      refute_includes result, sponsorship2,
        "should not include sponsorship for different $ amount than given custom tier"
      assert_includes result, sponsorship3
      refute_includes result, sponsorship4,
        "should not include sponsorship for different listing than given tier"
      assert_equal 2, result.size
    end
  end

  test "returns the first sponsorship for a sponsorable" do
    sponsorable = create(:user, :sponsorable)
    first_sponsorship = Timecop.freeze(2.days.ago) { create(:sponsorship, sponsorable: sponsorable) }
    Timecop.freeze(1.day.ago) { create(:sponsorship, sponsorable: sponsorable) }

    assert_equal first_sponsorship, Sponsorship.first_for(sponsorable: sponsorable)
  end

  test "returns true if sponsorship is first for a sponsorable" do
    sponsorable = create(:user, :sponsorable)
    first_sponsorship = Timecop.freeze(2.days.ago) { create(:sponsorship, sponsorable: sponsorable) }
    Timecop.freeze(1.day.ago) { create(:sponsorship, sponsorable: sponsorable) }

    assert first_sponsorship.first_for?(sponsorable: sponsorable)
  end

  # see https://github.com/github/sponsors/issues/4177
  test "returns false when first sponsorship is reactivated" do
    sponsorable = create(:user, :sponsorable)

    # create inactive first sponsorship
    first_sponsorship = travel_to(2.months.ago) { create(:sponsorship, :inactive, sponsorable: sponsorable) }
    refute_predicate first_sponsorship, :active

    # create other, newer sponsorship
    travel_to(1.month.ago) { create(:sponsorship, sponsorable: sponsorable) }

    # reactivate the first sponsorship
    first_sponsorship.update!(active: true)

    refute first_sponsorship.first_for?(sponsorable: sponsorable)
  end

  test "has_pending_cancellation? returns true when sponsorship is scheduled to be canceled" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

    create(:billing_pending_subscription_item_change,
      :cancellation,
      pending_plan_change: create(:billing_pending_plan_change, :active, user: @sponsor),
      subscribable: sponsorship.tier,
    )

    assert_predicate sponsorship, :has_pending_cancellation?
  end

  test "has_pending_cancellation? returns false when sponsor has unrelated pending cancellation" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

    create(:billing_pending_subscription_item_change,
      :cancellation,
      pending_plan_change: create(:billing_pending_plan_change, :active, user: @sponsor),
      subscribable: create(:sponsors_tier),
    )

    refute_predicate sponsorship, :has_pending_cancellation?
  end

  test "has_pending_cancellation? returns false when pending cancellation has completed" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

    create(:billing_pending_subscription_item_change,
      :cancellation,
      pending_plan_change: create(:billing_pending_plan_change, :inactive, user: @sponsor),
      subscribable: sponsorship.tier,
    )

    refute_predicate sponsorship, :has_pending_cancellation?
  end

  test "has_pending_cancellation? returns false when sponsorship is scheduled to be downgraded" do
    new_tier, old_tier =
      create(:sponsors_tier, :published, sponsors_listing: @listing)
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
      tier: old_tier)

    create(:billing_pending_subscription_item_change,
      pending_plan_change: create(:billing_pending_plan_change, :active, user: @sponsor),
      subscribable: new_tier,
      quantity: 1,
    )

    refute_predicate sponsorship, :has_pending_cancellation?
  end

  test "has_pending_cancellation? returns false when sponsor has no pending plan change" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    refute_predicate sponsorship, :has_pending_cancellation?
  end

  test "has_pending_cancellation? returns false when sponsorable is missing a SponsorsListing" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    @listing.delete
    @sponsorable.reload

    refute_predicate sponsorship, :has_pending_cancellation?
  end

  test "has_pending_activation? returns true when sponsorship is scheduled to be activated" do
    sponsorship = create(:sponsorship, :pending_activation, sponsor: @sponsor, sponsorable: @sponsorable)

    assert_predicate sponsorship, :has_pending_activation?
  end

  test "has_pending_activation? returns false when sponsorship has no pending change" do
    sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

    refute_predicate sponsorship, :has_pending_activation?
  end

  test "ranked_by_sponsor scope ranks by sponsor" do
    sponsor2 = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    sponsor3 = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))

    @rando.follow(sponsor2)

    sponsorship1 = Timecop.freeze(3.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    end
    sponsorship2 = Timecop.freeze(2.minutes.ago) do
      create(:sponsorship, sponsor: sponsor2, sponsorable: @sponsorable)
    end
    sponsorship3 = Timecop.freeze(1.minute.ago) do
      create(:sponsorship, sponsor: sponsor3, sponsorable: @sponsorable)
    end
    sponsorship_ids = [sponsorship1.id, sponsorship2.id, sponsorship3.id]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_by_sponsor(for_user: @rando)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship2, sponsorship1, sponsorship3], sorted_sponsorships
  end

  test "ranked_by_sponsor scope orders by sponsor_id when no ranking available" do
    sponsor2 = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    sponsor3 = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))

    @rando.follow(sponsor2)

    sponsorship1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    sponsorship2 = create(:sponsorship, sponsor: sponsor2, sponsorable: @sponsorable)
    sponsorship3 = create(:sponsorship, sponsor: sponsor3, sponsorable: @sponsorable)

    User.stubs(:ranked_for_ids).returns([])
    sorted_sponsorships = Sponsorship
      .where(id: [sponsorship1, sponsorship2, sponsorship3])
      .ranked_by_sponsor(for_user: @rando)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship1, sponsorship2, sponsorship3], sorted_sponsorships
  end

  test "ranked_by_sponsor scope does not rank when for_user is nil" do
    sponsor2 = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    sponsor3 = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))

    sponsorship1 = Timecop.freeze(3.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    end
    sponsorship2 = Timecop.freeze(2.minutes.ago) do
      create(:sponsorship, sponsor: sponsor2, sponsorable: @sponsorable)
    end
    sponsorship3 = Timecop.freeze(1.minute.ago) do
      create(:sponsorship, sponsor: sponsor3, sponsorable: @sponsorable)
    end
    sponsorship_ids = [sponsorship1.id, sponsorship2.id, sponsorship3.id]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_by_sponsor(for_user: nil)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship1, sponsorship2, sponsorship3], sorted_sponsorships
  end

  test "ranked_by_sponsor scope sorts private sponsorships to the end" do
    sponsor2 = create(
      :credit_card_user, plan_subscription: create(:billing_plan_subscription)
    )
    private_sponsor = create(
      :credit_card_user, plan_subscription: create(:billing_plan_subscription)
    )

    @rando.follow(sponsor2)
    @rando.follow(private_sponsor)

    sponsorship1 = Timecop.freeze(4.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    end
    sponsorship2 = Timecop.freeze(3.minutes.ago) do
      create(:sponsorship, sponsor: sponsor2, sponsorable: @sponsorable)
    end
    private_sponsorship = Timecop.freeze(1.minute.ago) do
      create(:sponsorship, :private, sponsor: private_sponsor, sponsorable: @sponsorable)
    end
    sponsorship_ids = [sponsorship1.id, sponsorship2.id, private_sponsorship.id]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_by_sponsor(for_user: @rando)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship2, sponsorship1, private_sponsorship], sorted_sponsorships
  end

  test "ranked_by_sponsorable scope ranks by sponsorable" do
    sponsorable2, sponsorable3 = create_list(:user, 2, :sponsorable)

    @rando.follow(sponsorable2)

    sponsorship1 = Timecop.freeze(3.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    end
    sponsorship2 = Timecop.freeze(2.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable2)
    end
    sponsorship3 = Timecop.freeze(1.minute.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable3)
    end
    sponsorship_ids = [sponsorship1.id, sponsorship2.id, sponsorship3.id]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_by_sponsorable(for_user: @rando)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship2, sponsorship1, sponsorship3], sorted_sponsorships
  end

  test "ranked_by_sponsorable scope sorts private sponsorships to the end" do
    sponsorable2, private_sponsorable = create_list(:user, 2, :sponsorable)

    @rando.follow(sponsorable2)
    @rando.follow(private_sponsorable)

    sponsorship1 = Timecop.freeze(3.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    end
    sponsorship2 = Timecop.freeze(2.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable2)
    end
    private_sponsorship = Timecop.freeze(1.minute.ago) do
      create(:sponsorship, :private, sponsor: @sponsor, sponsorable: private_sponsorable)
    end
    sponsorship_ids = [sponsorship1.id, sponsorship2.id, private_sponsorship.id]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_by_sponsorable(for_user: @rando)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship2, sponsorship1, private_sponsorship], sorted_sponsorships
  end

  test "ranked_by_sponsorable scope does not sort when for_user is nil" do
    sponsorable2, private_sponsorable = create_list(:user, 2, :sponsorable)

    sponsorship1 = Timecop.freeze(3.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
    end
    sponsorship2 = Timecop.freeze(2.minutes.ago) do
      create(:sponsorship, sponsor: @sponsor, sponsorable: sponsorable2)
    end
    private_sponsorship = Timecop.freeze(1.minute.ago) do
      create(:sponsorship, :private, sponsor: @sponsor, sponsorable: private_sponsorable)
    end
    sponsorship_ids = [sponsorship1.id, sponsorship2.id, private_sponsorship.id]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_by_sponsorable(for_user: nil)

    assert_equal 3, sorted_sponsorships.count
    assert_equal [sponsorship1, sponsorship2, private_sponsorship], sorted_sponsorships
  end

  test "ranked_for_public_profile scope ranks active -> inactive -> private" do
    inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable, created_at: 3.minutes.ago)
    private_sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable, created_at: 2.minutes.ago)
    inactive_private_sponsorship = create(:sponsorship, :private, :inactive, sponsorable: @sponsorable, created_at: 3.minutes.ago)
    active_sponsorship = create(:sponsorship, sponsorable: @sponsorable, created_at: 1.minute.ago)
    sponsorship_ids = [
      inactive_sponsorship.id,
      inactive_private_sponsorship.id,
      private_sponsorship.id,
      active_sponsorship.id
    ]

    sorted_sponsorships = Sponsorship.where(id: sponsorship_ids).ranked_for_public_profile

    assert_equal [
      active_sponsorship,
      private_sponsorship,
      inactive_sponsorship,
      inactive_private_sponsorship,
    ], sorted_sponsorships
  end

  context "when listing has an active goal" do
    test "completes goal when achieved" do
      goal = create(:sponsors_goal, :total_sponsors_count, :active,
        target_value: 1,
        listing: @listing,
      )

      assert_equal goal, @listing.reload.active_goal
      refute_predicate goal.reload, :can_complete?
      refute_predicate goal, :completed?
      assert_equal 0, goal.contributions.count

      perform_enqueued_jobs(only: CompleteSponsorsGoalJob) do
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @sponsor, sponsorable: @sponsorable)
      end

      assert_predicate goal.reload, :completed?
      assert_equal 1, goal.contributions.count
    end

    test "does not enqueue job if goal has not been reached" do
      goal = create(:sponsors_goal, :total_sponsors_count, :active,
        target_value: 2,
        listing: @listing,
      )

      assert_equal goal, @listing.reload.active_goal
      refute_predicate goal.reload, :can_complete?
      refute_predicate goal, :completed?
      assert_equal 0, goal.contributions.count

      assert_no_enqueued_jobs(only: CompleteSponsorsGoalJob) do
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @sponsor, sponsorable: @sponsorable)
      end

      refute_predicate goal.reload, :completed?
      assert_equal 0, goal.contributions.count
      assert_equal 0, goal.contributions.count
    end

    test "instruments near complete event if goal is near completion" do
      goal = create(:sponsors_goal, :monthly_sponsorship_amount, :active,
        target_value: 10,
        listing: @listing,
      )

      tier = create(:sponsors_tier, :published,
        sponsors_listing: @listing,
        monthly_price_in_cents: 9_00,
      )

      create(:sponsorship, :with_billing_transaction_and_line_item, tier: tier, sponsorable: @sponsorable)

      assert_predicate goal, :near_complete?
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.GoalEvent")
      assert_hydro_published({
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        goal: Hydro::EntitySerializer.sponsors_goal(goal),
        action: :NEAR_COMPLETED,
        sponsorable: Hydro::EntitySerializer.user(@sponsorable),
      }, schema: "github.sponsors.v1.GoalEvent")
    end

    test "does not instrument near complete event if goal has been completed" do
      goal = create(:sponsors_goal, :monthly_sponsorship_amount, :active,
        target_value: 10,
        listing: @listing,
      )

      tier = create(:sponsors_tier, :published,
        sponsors_listing: @listing,
        monthly_price_in_cents: 10_00,
      )

      create(:sponsorship, :with_billing_transaction_and_line_item, tier: tier, sponsorable: @sponsorable)

      assert_predicate goal, :can_complete?
      refute_predicate goal, :near_complete?
      refute_hydro_messages(schema: "github.sponsors.v1.GoalEvent")
    end

    test "does not instrument near complete event if goal is not near complete" do
      goal = create(:sponsors_goal, :monthly_sponsorship_amount, :active,
        target_value: 10,
        listing: @listing,
      )

      tier = create(:sponsors_tier, :published,
        sponsors_listing: @listing,
        monthly_price_in_cents: 5_00,
      )

      create(:sponsorship, :with_billing_transaction_and_line_item, tier: tier, sponsorable: @sponsorable)

      refute_predicate goal, :can_complete?
      refute_predicate goal, :near_complete?
      refute_hydro_messages(schema: "github.sponsors.v1.GoalEvent")
    end
  end

  context "when listing doesn't have an active goal" do
    test "does not enqueue job if goal" do
      assert_no_enqueued_jobs(only: CompleteSponsorsGoalJob) do
        create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      end
    end
  end

  context "#active_goal" do
    test "can be loaded efficiently for many sponsorships" do
      goal = create(:sponsors_goal, :total_sponsors_count, :active, target_value: 1, listing: @listing)
      sponsorship_with_goal1 = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      sponsorship_with_goal2 = create(:sponsorship, sponsorable: @sponsorable)

      sponsorship_without_goal1, sponsorship_without_goal2 = create_pair(:sponsorship, sponsor: @sponsor)

      sponsorships = [sponsorship_with_goal1, sponsorship_with_goal2, sponsorship_without_goal1,
        sponsorship_without_goal2]

      sponsorships.each(&:reload) # Clear out any loaded relations

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :active_goal)
      end

      assert_query_count(0) do
        assert_equal goal, sponsorship_with_goal1.active_goal
        assert_equal goal, sponsorship_with_goal2.active_goal
        assert_nil sponsorship_without_goal1.active_goal
        assert_nil sponsorship_without_goal2.active_goal
      end
    end
  end

  context "#send_new_sponsor_email?" do
    test "returns true for Zuora recurring sponsorship" do
      sponsorship = build(:sponsorship)
      assert_predicate sponsorship, :send_new_sponsor_email?
    end

    test "returns true for Zuora one-time sponsorship" do
      sponsorship = build(:sponsorship,
        sponsorable: @sponsorable,
        tier: @one_time_tier,
      )

      assert_predicate sponsorship, :send_new_sponsor_email?
    end

    test "returns true for invoiced sponsorship when transfer flag is true" do
      transfer = create(:invoiced_sponsorship_transfer, send_new_sponsor_email_on_transfer: true)
      sponsorship = create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

      assert_predicate sponsorship, :send_new_sponsor_email?
    end

    test "returns false for invoiced sponsorship when transfer flag is false" do
      transfer = create(:invoiced_sponsorship_transfer, send_new_sponsor_email_on_transfer: false)
      sponsorship = create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

      refute_predicate sponsorship, :send_new_sponsor_email?
    end
  end

  context "#new_sponsor_email_sent!" do
    test "no-op for recurring Zuora sponsorship" do
      sponsorship = build(:sponsorship)
      assert sponsorship.new_sponsor_email_sent!
    end

    test "no-op for one-time Zuora sponsorship" do
      sponsorship = build(:sponsorship,
        sponsorable: @sponsorable,
        tier: @one_time_tier,
      )

      assert sponsorship.new_sponsor_email_sent!
    end

    test "sets the new sponsor email timestamp for invoiced sponsorship" do
      sponsorship = create(:sponsorship, :invoiced)

      refute_predicate sponsorship.invoiced_sponsorship_transfer, :new_sponsor_email_sent?
      assert sponsorship.new_sponsor_email_sent!
      assert_predicate sponsorship.reload.invoiced_sponsorship_transfer, :new_sponsor_email_sent?
    end
  end

  context "#new_sponsor_email_note" do
    test "returns nil for recurring Zuora sponsorship" do
      sponsorship = build(:sponsorship)
      assert_nil sponsorship.new_sponsor_email_note
    end

    test "returns nil for one-time Zuora sponsorship" do
      sponsorship = build(:sponsorship,
        sponsorable: @sponsorable,
        tier: @one_time_tier,
      )

      assert_nil sponsorship.new_sponsor_email_note
    end

    test "returns the sponsor note for invoiced sponsorships" do
      transfer = create(:invoiced_sponsorship_transfer, new_sponsor_email_note: "Thank you test!")
      sponsorship = create(:sponsorship, :invoiced, invoiced_sponsorship_transfer: transfer)

      assert_equal "Thank you test!", sponsorship.new_sponsor_email_note
    end
  end

  context "#amount" do
    test "returns the tier's monthly price for monthly recurring sponsors" do
      sponsorship = create(:sponsorship,
        sponsorable: @sponsorable,
        sponsor: create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan_duration: "month",
        ),
      )

      expected_price = sponsorship.tier.base_price(duration: :month)
      assert_equal expected_price, sponsorship.amount
    end

    test "returns the tier's yearly price for yearly recurring sponsors" do
      sponsorship = create(:sponsorship,
        sponsorable: @sponsorable,
        sponsor: create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan_duration: "year",
        ),
      )

      expected_price = sponsorship.tier.base_price(duration: :year)
      assert_equal expected_price, sponsorship.amount
    end

    test "always returns the tier's yearly price for invoiced sponsorships" do
      sponsorship = create(:sponsorship, :invoiced,
        sponsor: create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan_duration: "month",
        ),
      )

      monthly_price = sponsorship.tier.base_price(duration: :month)
      expected_price = sponsorship.tier.base_price(duration: :year)

      refute_equal expected_price, monthly_price
      assert_equal expected_price, sponsorship.amount
    end
  end

  context "#amount_per_cycle" do
    test "returns the amount per cycle for recurring monthly sponsorships" do
      sponsorship = create(:sponsorship,
        sponsorable: @sponsorable,
        sponsor: create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan_duration: "month",
        ),
      )

      assert_equal "$#{sponsorship.amount} / month", sponsorship.amount_per_cycle
    end

    test "returns the amount per cycle for recurring yearly sponsorships" do
      sponsorship = create(:sponsorship,
        sponsorable: @sponsorable,
        sponsor: create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan_duration: "year",
        ),
      )

      assert_equal "$#{sponsorship.amount} / year", sponsorship.amount_per_cycle
    end

    test "returns the one-time amount for invoiced sponsorships" do
      sponsorship = create(:sponsorship, :invoiced)

      assert_equal "$#{sponsorship.amount} one time", sponsorship.amount_per_cycle
    end

    test "returns the one-time amount for Zuora one-time sponsorships" do
      sponsorship = create(:sponsorship,
        sponsorable: @sponsorable,
        tier: @one_time_tier,
      )

      assert_equal "$#{sponsorship.amount} one time", sponsorship.amount_per_cycle
    end
  end

  context "#tier_selected_date" do
    test "uses the subscribable_selected_at timestamp if present" do
      test_time = Time.parse("2063-04-05 12:00:00")

      sponsorship = travel_to(test_time) do
        create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier)
      end

      refute_nil sponsorship.subscribable_selected_at
      assert_equal test_time.to_date, sponsorship.tier_selected_date
    end

    test "uses the created_at timestamp if subscribable_selected_at is not present" do
      test_time = Time.parse("2063-04-05 12:00:00")

      sponsorship = travel_to(test_time) do
        create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier)
      end
      sponsorship.update_column(:subscribable_selected_at, nil)

      assert_nil sponsorship.subscribable_selected_at
      assert_equal test_time.to_date, sponsorship.tier_selected_date
    end
  end

  context "#tier_selected_on_or_before?" do
    test "true if tier was selected on the date" do
      test_time = Time.parse("2063-04-05 12:00:00")

      sponsorship = travel_to(test_time) do
        create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier)
      end

      present_date = test_time.to_date
      assert sponsorship.tier_selected_on_or_before?(present_date)
    end

    test "true if tier was selected before the date" do
      test_time = Time.parse("2063-04-05 12:00:00")

      sponsorship = travel_to(test_time) do
        create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier)
      end

      future_date = test_time.to_date + 1.day
      assert sponsorship.tier_selected_on_or_before?(future_date)
    end

    test "false if tier was selected after the date" do
      test_time = Time.parse("2063-04-05 12:00:00")

      sponsorship = travel_to(test_time) do
        create(:sponsorship, sponsorable: @sponsorable, tier: @recurring_tier)
      end

      past_date = test_time.to_date - 1.day
      refute sponsorship.tier_selected_on_or_before?(past_date)
    end
  end

  context "#concurrent_payment?" do
    test "returns true if current recurring sponsorship and tier paid is one-time" do
      sponsorship = create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @recurring
      )

      assert sponsorship.concurrent_payment?(tier_paid: @one_time_tier)
    end

    test "returns false if current recurring sponsorship and tier paid is one-time for another listing" do
      sponsorship = create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @recurring_tier
      )

      different_listing_one_time_tier = create(:sponsors_tier, :published, :one_time)

      refute sponsorship.concurrent_payment?(tier_paid: different_listing_one_time_tier)
    end

    test "returns false if current recurring sponsorship and tier paid is recurring" do
      sponsorship = create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @recurring_tier
      )

      other_recurring_tier = create(:sponsors_tier, :published,
        sponsors_listing: sponsorship.sponsors_listing
      )

      refute sponsorship.concurrent_payment?(tier_paid: @recurring_tier)
      refute sponsorship.concurrent_payment?(tier_paid: other_recurring_tier)
    end

    test "returns false if current one-time sponsorship" do
      sponsorship = create(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @one_time_tier
      )

      refute sponsorship.concurrent_payment?(tier_paid: @one_time_tier)
      refute sponsorship.concurrent_payment?(tier_paid: @recurring_tier)
    end

    test "returns false if tier_paid is nil" do
      sponsorship = build(:sponsorship,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        tier: @one_time_tier
      )

      refute sponsorship.concurrent_payment?(tier_paid: nil)
    end
  end

  context "#sponsors_only_repository" do
    test "returns sponsorship's tier's repository when set and sponsor is a user" do
      tier_with_repo = build(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      sponsorship = build(:sponsorship, tier: tier_with_repo)

      assert_equal tier_with_repo.repository, sponsorship.sponsors_only_repository
    end

    test "returns nil when sponsorship's tier's repository is set but sponsor is an organization" do
      tier_with_repo = build(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      sponsorship = build(:sponsorship, :from_org, tier: tier_with_repo)

      assert_nil sponsorship.sponsors_only_repository
    end

    test "returns nil when sponsorship's tier has no repository" do
      sponsorship = build(:sponsorship, tier: @recurring_tier)
      assert_nil sponsorship.sponsors_only_repository
    end

    test "returns sponsorship's custom tier's parent tier's repository when set" do
      tier_with_repo = build(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      custom_tier = build(:sponsors_tier, :custom, parent_tier: tier_with_repo)
      sponsorship = build(:sponsorship, tier: custom_tier)

      assert_equal tier_with_repo.repository, sponsorship.sponsors_only_repository
    end

    test "returns sponsorship's custom tier's closest lesser-value tier's repository when parent_tier is not set" do
      tier_with_repo = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      custom_tier = build(:sponsors_tier, :custom, sponsors_listing: @listing,
        monthly_price_in_cents: tier_with_repo.monthly_price_in_cents + 100, parent_tier: nil)
      sponsorship = build(:sponsorship, tier: custom_tier)

      assert_equal tier_with_repo.repository, sponsorship.sponsors_only_repository
    end

    test "returns nil when sponsorship's custom tier does not have a parent tier or a lesser-value tier that has a repository" do
      listing = create(:sponsors_listing, :approved, tier_count: 0)

      # Make a tier with a repo but whose price exceeds that of the custom tier, to ensure this tier's repo is
      # *not* returned:
      create(:sponsors_tier, :published, :with_repository, sponsors_listing: listing, monthly_price_in_cents: 50_00)

      custom_tier = build(:sponsors_tier, :custom, sponsors_listing: listing, parent_tier: nil,
        monthly_price_in_cents: 25_00)
      sponsorship = build(:sponsorship, tier: custom_tier)

      assert_nil sponsorship.sponsors_only_repository
    end
  end

  context "#equally_priced_tier?" do
    test "returns true when given a SponsorsPatreonTier with the same monthly cost as the sponsorship's tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: sponsorship.monthly_price_in_cents)
      assert sponsorship.equally_priced_tier?(patreon_tier)
    end

    test "returns false when given a SponsorsPatreonTier with a different monthly cost than the sponsorship" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: sponsorship.monthly_price_in_cents + 1_00)
      refute sponsorship.equally_priced_tier?(patreon_tier)
    end

    test "returns true when given a SponsorsTier with the same monthly cost as the sponsorship's tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      other_tier = SponsorsTier.new(monthly_price_in_cents: sponsorship.monthly_price_in_cents,
        yearly_price_in_cents: sponsorship.monthly_price_in_cents * 12)
      assert sponsorship.equally_priced_tier?(other_tier)
    end

    test "returns false when given a SponsorsTier with a different monthly cost as the sponsorship's tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      other_tier = SponsorsTier.new(monthly_price_in_cents: sponsorship.monthly_price_in_cents + 2_00,
        yearly_price_in_cents: (sponsorship.monthly_price_in_cents + 2_00) * 12)
      refute sponsorship.equally_priced_tier?(other_tier)
    end
  end

  context "#equal_tier?" do
    test "returns true when tier and new_tier are the same object" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      assert sponsorship.equal_tier?(sponsorship.tier)
    end

    test "returns false when new_tier is not a sponsorship tier" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      refute sponsorship.equal_tier?(nil)
    end

    test "returns false when new_tier is custom and existing tier is not" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

      custom_tier = build(:sponsors_tier, :custom, sponsors_listing: @listing, monthly_price_in_cents: 100)

      refute sponsorship.equal_tier?(custom_tier)
    end

    test "returns false when custom tiers differ in price" do
      custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @listing,
        monthly_price_in_cents: 800)
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: custom_tier)

      new_tier = build(:sponsors_tier, :custom, sponsors_listing: @listing,
          monthly_price_in_cents: 100)

      refute sponsorship.equal_tier?(new_tier)
    end

    test "returns false when tiers belong to different listings" do
      custom_tier = create(:sponsors_tier, :custom, :one_time, sponsors_listing: @listing,
        monthly_price_in_cents: 100)
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: custom_tier)

      new_listing = create(:sponsors_listing)
      new_tier = build(:sponsors_tier, :custom, :one_time, sponsors_listing: new_listing,
        monthly_price_in_cents: 100)

      refute sponsorship.equal_tier?(new_tier)
    end

    # https://github.com/github/sponsors/issues/3025
    test "returns false for tiers using the same amount but different frequencies" do
      monthly_amount_in_cents = 500_00

      # one time tiers usually have the same monthly & yearly price
      # but we see this happen in production: https://data.githubapp.com/sql/share/a97b9efc
      one_time_tier = create(:sponsors_tier, :custom, :one_time, sponsors_listing: @listing,
        monthly_price_in_cents: monthly_amount_in_cents, yearly_price_in_cents: 12 * monthly_amount_in_cents)

      recurring_tier = create(:sponsors_tier, :custom, :recurring, sponsors_listing: @listing,
        monthly_price_in_cents: monthly_amount_in_cents)

      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: recurring_tier)
      refute sponsorship.equal_tier?(one_time_tier)
    end
  end

  context "#started_after_sponsors_public_release?" do
    test "true if started after fee GA date" do

      travel_to Sponsorship::SPONSORS_PUBLIC_RELEASE_DATE + 1.day do
        sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

        assert_predicate sponsorship, :started_after_sponsors_public_release?
      end
    end

    test "false if started before fee GA date" do
      travel_to Sponsorship::SPONSORS_PUBLIC_RELEASE_DATE - 1.day do
        sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)

        refute_predicate sponsorship, :started_after_sponsors_public_release?
      end
    end

    test "false if subscribable_selected_at is nil" do
      travel_to Sponsorship::SPONSORS_PUBLIC_RELEASE_DATE + 1.day do
        sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
        sponsorship.update!(subscribable_selected_at: nil)

        refute_predicate sponsorship, :started_after_sponsors_public_release?
      end
    end
  end

  context "#pending_activation_date" do
    test "returns the pending activation date if a pending activation exists" do
      sponsorship = create(:sponsorship, quantity: 0)
      sponsor = sponsorship.sponsor
      active_on = sponsor.next_sponsors_billing_date
      pending_plan_change = create(:billing_pending_plan_change,
        user: sponsor,
        active_on: active_on,
      )
      pending_sub_item_change = create(:billing_pending_subscription_item_change,
        pending_plan_change: pending_plan_change,
        quantity: 1,
        subscribable: sponsorship.tier,
        account: sponsor,
      )

      assert_equal Sponsorship::PendingChange::Type::Activation, sponsorship.pending_change.type
      assert_equal active_on, sponsorship.pending_activation_date
    end

    test "returns nil if pending change is not an activation" do
      sponsor = @basic_sponsorship.sponsor
      pending_sub_item_change = create(:billing_pending_subscription_item_change,
        subscribable: @basic_sponsorship.tier,
        quantity: 0,
        account: sponsor,
      )

      assert_equal Sponsorship::PendingChange::Type::Cancellation, @basic_sponsorship.pending_change.type
      assert_nil @basic_sponsorship.pending_activation_date
    end

    test "returns nil if sponsorship does not have a pending change" do
      assert_nil @basic_sponsorship.pending_change
      assert_nil @basic_sponsorship.pending_activation_date
    end
  end
end if GitHub.sponsors_enabled?
