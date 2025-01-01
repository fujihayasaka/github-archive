# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSponsorsDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved,
      tier_count: 3)
    @sponsorable = @sponsors_listing.sponsorable
    @sponsorship1, @sponsorship2, @sponsorship3 = create_list(:sponsorship, 3,
      sponsorable: @sponsorable, tier: @sponsors_listing.default_tier)
    @one_time_tier = create(:sponsors_tier, :published, :one_time,
      sponsors_listing: @sponsors_listing)

    @sponsorable_no_sponsors = create(:user, :sponsorable)

    @org = create(:organization, :sponsorable)

    @sponsor = create(:credit_card_user, :verified)
    @sponsor_pub_repo = travel_to(1.hour.ago) { create(:repository, owner: @sponsor) }
    @sponsor_priv_repo = create(:private_repository, owner: @sponsor)
    @sponsorships_for_sponsor = create_list(:sponsorship, 3, sponsor: @sponsor)
    @sponsor.sponsors_plan_subscription.update!(
      zuora_subscription_id: SecureRandom.hex(16),
      zuora_subscription_number: "A-S#{SecureRandom.hex(6)}"
    )
    @sponsor.customer.update!(bill_cycle_day: 1)

    @org_sponsor_admin = create(:user)
    @org_sponsor = create(:credit_card_org, admin: @org_sponsor_admin)
    @org_sponsor_pub_repo = travel_to(1.hour.ago) do
      create(:repository, owner: @org_sponsor, organization: @org_sponsor)
    end
    @org_sponsor_priv_repo = create(:private_repository, owner: @org_sponsor, organization: @org_sponsor)
    @sponsorship_with_org_sponsor = create(:sponsorship, sponsor: @org_sponsor)
    @one_time_sponsorship_with_org_sponsor = create(:sponsorship, :one_time, sponsor: @org_sponsor)

    @billing_manager = create(:user)

    @public_org_member = create(:credit_card_user)
    @private_org_member = create(:user)

    @non_sponsor = create(:user, :verified)

    @fiscal_host_listing = create(:sponsors_listing, :fiscal_host, sponsorable_login: "numfocus")
    @fiscal_stripe = create(:stripe_connect_account, sponsors_listing: @fiscal_host_listing)
    @child_listing = create(:sponsors_listing, :with_fiscal_host,
      parent_listing: @fiscal_host_listing)

    @staff = create(:staff_admin_user)

    if GitHub.spamminess_check_enabled?
      @spammy_sponsorable = create(:spammy_user, :verified, :sponsorable)
    end

    unless GitHub.single_business_environment?
      @business = create(:business)
    end

    @org_that_gets_credit = create(:organization)
    @org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
    create(:organization_profile, organization: @org_that_gets_credit, sponsoring_linked_organization: @org_that_pays)

    @org_that_gets_credit_billing_manager = create(:user)
    @org_that_gets_credit.billing.add_manager(@org_that_gets_credit_billing_manager,
      actor: @org_that_gets_credit.admin)

    @invoiced_org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)

    @org_sponsor.add_member(@public_org_member)
    @org_sponsor.add_member(@private_org_member)
    @org_sponsor.billing.add_manager(@billing_manager, actor: @org_sponsor_admin)

    @org_sponsor.publicize_member(@public_org_member)
  end

  context "#sponsors_customer" do
    test "returns Sponsors-specific customer even if a general-purpose customer exists for the user" do
      general_purpose_customer = create(:customer_account, user: @non_sponsor).customer
      sponsors_customer = create(:customer, :sponsors_invoiced, payment_method: build(:payment_method, primary: false))
      create(:customer_account, :sponsors_invoiced, user: @non_sponsor, customer: sponsors_customer)

      assert_equal sponsors_customer, @non_sponsor.sponsors_customer
    end

    test "does not make additional queries with repeated calls" do
      sponsors_customer = create(:customer, :sponsors_invoiced, payment_method: build(:payment_method, primary: false))
      create(:customer_account, :sponsors_invoiced, user: @non_sponsor, customer: sponsors_customer)

      assert_query_count(1) do
        assert_equal sponsors_customer, @non_sponsor.sponsors_customer
      end

      assert_query_count(0) do
        assert_equal sponsors_customer, @non_sponsor.sponsors_customer
      end
    end

    test "does not make an additional query to the general-purpose customer when calling #customer after" do
      general_purpose_customer = create(:customer_account, user: @non_sponsor).customer

      @non_sponsor.sponsors_customer # load all the customers tied to the user

      assert_query_count(0) do
        assert_equal general_purpose_customer, @non_sponsor.customer
      end
    end
  end

  context "#save_bulk_sponsorship_tier_ids" do
    test "writes sorted list of given tier IDs to tier selection record" do
      tier2 = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      assert_operator tier2.id, :>, @one_time_tier.id, "need a tier ID that comes later than another tier's ID"
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      sponsorship2 = create(:sponsorship, tier: tier2, sponsor: sponsor, sponsorable: tier2.sponsorable)

      assert sponsor.save_bulk_sponsorship_tier_ids([tier2.id, @one_time_tier.id]) # provided in wrong sort order

      tier_selection = sponsor.reload_bulk_sponsorship_tier_selection
      refute_nil tier_selection
      assert_equal [@one_time_tier.id, tier2.id], tier_selection.sponsors_tier_ids, "IDs should be sorted"
    end

    test "creates a BulkSponsorshipTierSelection when the user does not have one" do
      assert_nil @sponsor.bulk_sponsorship_tier_selection, "need a user without a BulkSponsorshipTierSelection"

      assert_difference("BulkSponsorshipTierSelection.count") do
        assert @sponsor.save_bulk_sponsorship_tier_ids([@one_time_tier.id])
      end

      refute_nil @sponsor.reload_bulk_sponsorship_tier_selection
      assert_equal [@one_time_tier.id], @sponsor.bulk_sponsorship_tier_selection.sponsors_tier_ids
    end

    test "updates the user's existing BulkSponsorshipTierSelection when they have one" do
      other_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      create(:bulk_sponsorship_tier_selection, sponsor: @sponsor, sponsors_tier_ids: [other_tier.id])

      assert_no_difference("BulkSponsorshipTierSelection.count") do
        assert @sponsor.save_bulk_sponsorship_tier_ids([@one_time_tier.id])
      end

      assert_equal [@one_time_tier.id], @sponsor.reload_bulk_sponsorship_tier_selection.sponsors_tier_ids,
        "should have replaced tier list with the exact one given"
    end

    test "does not write anything to tier selection record when given list is empty" do
      assert_nil @sponsor.bulk_sponsorship_tier_selection, "need a user without a BulkSponsorshipTierSelection"

      assert_no_difference("BulkSponsorshipTierSelection.count") do
        refute @sponsor.save_bulk_sponsorship_tier_ids([])
      end

      assert_nil @sponsor.reload_bulk_sponsorship_tier_selection
    end
  end

  context "#save_bulk_sponsorship_import" do
    test "writes given list to new bulk sponsorship import record" do
      amounts_and_sponsorables = [
        { sponsorable_login: "maintainer1", amount: 5 },
        { sponsorable_login: "aNiceOrg", amount: "350.00" },
      ]
      assert_nil @sponsor.bulk_sponsorship_import, "need a user without a BulkSponsorshipImport"

      assert_difference("BulkSponsorshipImport.count") do
        assert @sponsor.save_bulk_sponsorship_import(amounts_and_sponsorables)
      end

      refute_nil @sponsor.reload_bulk_sponsorship_import
      assert_equal [
        { "sponsorable_login" => "maintainer1", "amount" => 5 },
        { "sponsorable_login" => "aNiceOrg", "amount" => "350.00" },
      ], @sponsor.bulk_sponsorship_import.data
    end

    test "writes given list to existing bulk sponsorship import record" do
      amounts_and_sponsorables = [
        { sponsorable_login: "maintainer1", amount: 5 },
        { sponsorable_login: "aNiceOrg", amount: "350.00" },
      ]
      import = create(:bulk_sponsorship_import, sponsor: @sponsor)

      assert_no_difference("BulkSponsorshipImport.count") do
        assert @sponsor.save_bulk_sponsorship_import(amounts_and_sponsorables)
      end

      assert_equal [
        { "sponsorable_login" => "maintainer1", "amount" => 5 },
        { "sponsorable_login" => "aNiceOrg", "amount" => "350.00" },
      ], @sponsor.reload_bulk_sponsorship_import.data
    end

    test "does not write anything to bulk sponsorship import table when given list is empty" do
      assert_nil @sponsor.bulk_sponsorship_import, "need a user without a BulkSponsorshipImport"

      refute @sponsor.save_bulk_sponsorship_import([])

      assert_nil @sponsor.reload_bulk_sponsorship_import, "user should still not have a BulkSponsorshipImport"
    end
  end

  context "#amounts_by_sponsorable_login_bulk_sponsorship_import" do
    test "returns empty list when nothing exists for the sponsor in the bulk sponsorship import table" do
      assert_nil @sponsor.bulk_sponsorship_import
      assert_equal [], @sponsor.amounts_by_sponsorable_login_bulk_sponsorship_import
    end

    test "returns a list of hashes that were saved for the sponsor" do
      @sponsor.save_bulk_sponsorship_import([
        { sponsorable_login: @sponsorable.login, amount: 5 },
        { sponsorable_login: @sponsorable_no_sponsors.login, amount: "$12.00" },
      ])

      assert_equal [
        { "sponsorable_login" => @sponsorable.login, "amount" => 5 },
        { "sponsorable_login" => @sponsorable_no_sponsors.login, "amount" => "$12.00" },
      ], @sponsor.amounts_by_sponsorable_login_bulk_sponsorship_import
    end

    test "returns list of hashes in saved bulk sponsorship import record" do
      data = [
        { "sponsorable_login" => @sponsorable.login, "amount" => 5 },
        { "sponsorable_login" => @sponsorable_no_sponsors.login, "amount" => "$12.00" },
      ]
      create(:bulk_sponsorship_import, sponsor: @sponsor, data: data)

      assert_equal data, @sponsor.amounts_by_sponsorable_login_bulk_sponsorship_import
    end

    test "will not return hashes from bulk sponsorship import record when the record is expired" do
      data = [
        { "sponsorable_login" => @sponsorable.login, "amount" => 5 },
        { "sponsorable_login" => @sponsorable_no_sponsors.login, "amount" => "$12.00" },
      ]
      travel_to((BulkSponsorshipImport::HOURS_UNTIL_EXPIRATION + 1).hours.ago) do
        create(:bulk_sponsorship_import, sponsor: @sponsor, data: data)
      end

      assert_empty @sponsor.amounts_by_sponsorable_login_bulk_sponsorship_import
    end
  end

  context "#sponsors_payment_method" do
    test "limits queries for a user with no payment method" do
      expected_queries_by_table = { customers: 1 }

      # Clear any cached relations:
      @non_sponsor.reload

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          assert_nil @non_sponsor.sponsors_payment_method
        end
      end
    end

    test "limits queries for a user with only a general-purpose payment method" do
      payment_method = @sponsor.customer.payment_method

      expected_queries_by_table = { customers: 1, payment_methods: 1 }

      # Clear any cached relations:
      @sponsor.reload

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          assert_equal payment_method, @sponsor.sponsors_payment_method
        end
      end
    end

    test "limits queries for a user with only a Sponsors-purpose payment method" do
      user = create(:user)
      customer_account = create(:credit_card_customer_account, purpose: :sponsors, user: user)
      payment_method = customer_account.customer.payment_method

      expected_queries_by_table = { customers: 1, payment_methods: 1 }

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          assert_equal payment_method, user.sponsors_payment_method
        end
      end
    end

    test "limits queries for a user with both a Sponsors-purpose and a general-purpose payment method" do
      user = create(:user)
      create(:credit_card_customer_account, user: user)
      sponsors_customer = create(:credit_card_customer, :sponsors_invoiced, customer_account_user: user,
        payment_method: build(:paypal_payment_method, user: user, primary: false, customer: nil))
      payment_method = sponsors_customer.payment_method

      expected_queries_by_table = { customers: 1, payment_methods: 1 }

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          assert_equal payment_method, user.sponsors_payment_method
        end
      end
    end
  end

  context "#instrument_sponsorship_payment_complete" do
    test "emits a Hydro event for sponsorships from the user for maintainers with the given tiers" do
      sponsorship1, sponsorship2 = @sponsorships_for_sponsor.take(2)
      tier1 = sponsorship1.tier
      tier2 = sponsorship2.tier
      refute_equal tier1, tier2
      refute_equal tier1.sponsors_listing_id, tier2.sponsors_listing_id,
        "need sponsorships for two different maintainers"

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 2) do
        @sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [tier1, tier2])
      end

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
        listing: Hydro::EntitySerializer.sponsors_listing(tier1.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(tier1),
        via_bulk_sponsorship: false,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
        listing: Hydro::EntitySerializer.sponsors_listing(tier2.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(tier2),
        via_bulk_sponsorship: false,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    # https://github.com/github/sponsors/issues/4636#issuecomment-1409111240
    test "updates paid_at on the sponsorships only if the tier on the sponsorship is the one that was paid" do
      tier = @sponsorship1.tier
      other_tier = @sponsors_listing.sponsors_tiers.last
      refute_equal tier, other_tier, "need two different tiers"
      assert_equal tier.listing_id, other_tier.listing_id, "need two tiers for the same listing"

      paid_at = @sponsorship1.paid_at
      sponsor = @sponsorship1.sponsor

      travel_to(@sponsorship1.paid_at + 1.hour) do
        # should not update paid_at since the tier is not the one on the active sponsorship
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [other_tier])
        assert_equal paid_at, @sponsorship1.reload.paid_at

        # should update paid_at since the tier is the one on the active sponsorship
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [tier])
        assert_operator paid_at, :<, @sponsorship1.reload.paid_at,
          "should have updated sponsorship paid_at to be later than it was before"
      end
    end

    test "sets via_bulk_sponsorship=true when multiple one-time tiers are given" do
      tier2 = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      tiers = [@one_time_tier, tier2]
      tier_ids = tiers.map(&:id)
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      sponsorship2 = create(:sponsorship, tier: tier2, sponsor: sponsor, sponsorable: tier2.sponsorable)

      # Mark tiers tied to a bulk sponsorship as unpaid by storing their IDs in KV
      sponsor.save_bulk_sponsorship_tier_ids(tier_ids)

      assert_same_elements tier_ids, sponsor.payment_incomplete_bulk_sponsorship_tier_ids

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 2) do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: tiers)
      end

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        via_bulk_sponsorship: true,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
        listing: Hydro::EntitySerializer.sponsors_listing(tier2.sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(tier2),
        via_bulk_sponsorship: true,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    end

    test "removes paid tier from stored bulk sponsorship in GitHub KV" do
      tier2, tier3 = create_pair(:sponsors_tier, :approved_sponsors_listing, :one_time)
      tiers = [@one_time_tier, tier2, tier3]
      tier_ids = tiers.map(&:id)
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      sponsorship2 = create(:sponsorship, tier: tier2, sponsor: sponsor, sponsorable: tier2.sponsorable)
      sponsorship3 = create(:sponsorship, tier: tier3, sponsor: sponsor, sponsorable: tier3.sponsorable)

      # Mark tiers tied to a bulk sponsorship as unpaid by storing their IDs in KV
      sponsor.save_bulk_sponsorship_tier_ids(tier_ids)

      assert_same_elements tier_ids, sponsor.payment_incomplete_bulk_sponsorship_tier_ids

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 1) do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [@one_time_tier])
      end

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        via_bulk_sponsorship: true,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")

      assert_same_elements Set.new([tier2.id, tier3.id]), sponsor.payment_incomplete_bulk_sponsorship_tier_ids
    end

    test "removes bulk sponsorship tier selection record if no tiers remain to be paid" do
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      tier = @one_time_tier
      tier_ids = [tier.id]

      # Mark tiers tied to a bulk sponsorship as unpaid by storing their IDs in tier selection record
      sponsor.save_bulk_sponsorship_tier_ids(tier_ids)
      assert_same_elements tier_ids, sponsor.payment_incomplete_bulk_sponsorship_tier_ids

      assert_hydro_message_difference("github.sponsors.v1.SponsorshipPaymentComplete", 1) do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [tier])
      end

      assert_hydro_published_partial({
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
        listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        via_bulk_sponsorship: true,
      }, schema: "github.sponsors.v1.SponsorshipPaymentComplete")

      assert_nil sponsor.reload.bulk_sponsorship_tier_selection
    end

    test "queues now_sponsoring_via_bulk_sponsorship email job when there are unpaid tiers stored in KV" do
      tier2 = create(:sponsors_tier, :approved_sponsors_listing, :recurring)
      tiers = [@one_time_tier, tier2]
      tier_ids = tiers.map(&:id)
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      sponsorship2 = create(:sponsorship, tier: tier2, sponsor: sponsor, sponsorable: tier2.sponsorable)

      # Mark tiers tied to a bulk sponsorship as unpaid by storing their IDs in KV
      sponsor.save_bulk_sponsorship_tier_ids(tier_ids)

      assert_same_elements tier_ids, sponsor.payment_incomplete_bulk_sponsorship_tier_ids

      assert_enqueued_with(job: SendNowSponsoringViaBulkSponsorshipEmailJob, args: [{
        sponsor: sponsor,
        tiers_paid: tiers,
      }], queue: "sponsors_emails") do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [tier2, @one_time_tier])
      end
    end

    test "queues now_sponsoring_via_bulk_sponsorship email job as tiers are paid" do
      tier2, tier3 = create_pair(:sponsors_tier, :approved_sponsors_listing, :recurring)
      tiers = [@one_time_tier, tier2, tier3]
      tier_ids = tiers.map(&:id)
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      sponsorship2 = create(:sponsorship, tier: tier2, sponsor: sponsor, sponsorable: tier2.sponsorable)
      sponsorship3 = create(:sponsorship, tier: tier3, sponsor: sponsor, sponsorable: tier3.sponsorable)

      # Mark tiers tied to a bulk sponsorship as unpaid by storing their IDs in KV
      sponsor.save_bulk_sponsorship_tier_ids(tier_ids)

      assert_enqueued_with(job: SendNowSponsoringViaBulkSponsorshipEmailJob, args: [{
        sponsor: sponsor,
        tiers_paid: [@one_time_tier, tier2],
      }], queue: "sponsors_emails") do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [@one_time_tier, tier2])
      end

      assert_enqueued_with(job: SendNowSponsoringViaBulkSponsorshipEmailJob, args: [{
        sponsor: sponsor,
        tiers_paid: [tier3],
      }], queue: "sponsors_emails") do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [tier3])
      end
    end

    test "does not queue now_sponsoring_via_bulk_sponsorship email job when there are no unpaid tiers stored in KV" do
      tier2 = create(:sponsors_tier, :approved_sponsors_listing, :recurring)
      tiers = [@one_time_tier, tier2]
      sponsorship1 = create(:sponsorship, tier: @one_time_tier, sponsorable: @sponsorable)
      sponsor = sponsorship1.sponsor
      sponsorship2 = create(:sponsorship, tier: tier2, sponsor: sponsor, sponsorable: tier2.sponsorable)

      assert_empty sponsor.payment_incomplete_bulk_sponsorship_tier_ids

      assert_enqueued_jobs 0, only: SendNowSponsoringViaBulkSponsorshipEmailJob do
        sponsor.instrument_sponsorship_payment_complete(sponsors_tiers: [tier2, @one_time_tier])
      end
    end
  end

  context "#payment_incomplete_bulk_sponsorship_tier_ids" do
    test "returns tier IDs from BulkSponsorshipTierSelection when user has one" do
      tier_selection = create(:bulk_sponsorship_tier_selection, sponsor: @sponsor,
        sponsors_tier_ids: [@one_time_tier.id])

      assert_equal Set.new([@one_time_tier.id]), @sponsor.payment_incomplete_bulk_sponsorship_tier_ids
    end

    test "returns an empty set when no BulkSponsorshipTierSelection exists for the user" do
      assert_nil @sponsor.bulk_sponsorship_tier_selection, "need a user without a BulkSponsorshipTierSelection"

      assert_equal Set.new, @sponsor.payment_incomplete_bulk_sponsorship_tier_ids
    end
  end

  context "#clear_bulk_sponsorship_tier_ids" do
    test "deletes the BulkSponsorshipTierSelection when the user has one" do
      tier_selection = create(:bulk_sponsorship_tier_selection, sponsor: @sponsor,
        sponsors_tier_ids: [@one_time_tier.id])

      assert_difference("BulkSponsorshipTierSelection.count", -1) do
        @sponsor.clear_bulk_sponsorship_tier_ids
      end

      refute BulkSponsorshipTierSelection.exists?(tier_selection.id)
    end
  end

  context "#sponsors_zuora_account?" do
    test "true when the user has a Sponsors-specific customer record with a zuora_account_id" do
      customer = Customer.new(purpose: :sponsors, zuora_account_id: SecureRandom.hex(16))
      user = build(:user, sponsors_customer: customer)

      assert_predicate user, :sponsors_zuora_account?
    end

    test "false when the user has a Sponsors-specific customer record without a zuora_account_id" do
      customer = Customer.new(purpose: :sponsors, zuora_account_id: nil)
      user = build(:user, sponsors_customer: customer)

      refute_predicate user, :sponsors_zuora_account?
    end

    test "false when the user has no Sponsors-specific customer record" do
      customer = Customer.new(purpose: :general, zuora_account_id: SecureRandom.hex(16))
      user = build(:user, customer: customer)

      refute_predicate user, :sponsors_zuora_account?
    end
  end

  context "sponsors_zero_balance_date" do
    test "nil if not Sponsors invoiced" do
      sponsorship = create(:sponsorship)
      sponsor = sponsorship.sponsor

      assert_nil sponsor.sponsors_zero_balance_date
    end

    test "returns date if Sponsors invoiced" do
      freeze_time

      billing_today = GitHub::Billing.today
      expected_date = billing_today + 2.months

      sponsorship = create(:sponsorship, :sponsors_invoiced, monthly_price_in_cents: 50_00)
      sponsor = sponsorship.sponsor
      customer = sponsor.sponsors_customer
      customer.update!(bill_cycle_day: billing_today.day)
      customer.stubs(:credit_balance).returns(Billing::Money.new(100_00))

      assert_equal expected_date, sponsor.sponsors_zero_balance_date
    end

    # See https://github.com/github/sponsors/issues/5174
    test "ignores one-time sponsorships" do
      freeze_time

      billing_today = GitHub::Billing.today
      expected_date = billing_today + 2.months

      sponsorship = create(:sponsorship, :sponsors_invoiced, monthly_price_in_cents: 50_00)
      sponsor = sponsorship.sponsor
      create(:sponsorship, :one_time, :paid, sponsor: sponsor, monthly_price_in_cents: 100_00)

      customer = sponsor.sponsors_customer
      customer.update!(bill_cycle_day: billing_today.day)
      customer.stubs(:credit_balance).returns(Billing::Money.new(100_00))

      assert_equal expected_date, sponsor.sponsors_zero_balance_date
    end
  end

  context "#has_paypal_account_for_sponsors?" do
    test "returns true when Sponsors-specific payment method is PayPal" do
      user = create(:paypal_customer_account, :sponsors_invoiced).user
      assert_predicate user, :has_paypal_account_for_sponsors?
    end

    test "returns false when Sponsors-specific payment method is credit card even if general-purpose payment method is PayPal" do
      user = create(:credit_card_customer_account, :sponsors_invoiced).user
      refute_predicate user, :has_paypal_account_for_sponsors?

      general_customer = create(:paypal_customer, purpose: :general)
      create(:customer_account, customer: general_customer, user: user)
      refute_predicate user.reload, :has_paypal_account_for_sponsors?, "should still look at Sponsors-specific method"
    end

    test "returns true when general-purpose payment method is PayPal and no Sponsors-specific payment method exists" do
      user = create(:paypal_customer_account).user
      assert_predicate user, :has_paypal_account_for_sponsors?
    end

    test "returns false when general-purpose payment method is credit card and no Sponsors-specific payment method exists" do
      user = create(:credit_card_customer_account).user
      refute_predicate user, :has_paypal_account_for_sponsors?
    end

    test "returns false for user with no payment methods" do
      user = create(:user)
      refute_predicate user, :has_paypal_account_for_sponsors?
    end

    test "returns false for Sponsors-invoiced customer, even if they have PayPal for a general-purpose payment method" do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      assert_predicate org, :sponsors_invoiced?
      create(:paypal_payment_method, customer: org.customer)
      refute_predicate org, :has_paypal_account_for_sponsors?
    end
  end

  context "#cancel_sponsorships_from_and_to" do
    test "cancels sponsorship from the user to the specified user" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      other_user = sponsorship.sponsorable

      assert @sponsor.cancel_sponsorships_from_and_to(other_user, actor: @sponsor)

      refute_predicate sponsorship.reload, :active?
    end

    test "cancels sponsorship to the user from the specified user" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      user = sponsorship.sponsorable

      assert user.cancel_sponsorships_from_and_to(@sponsor, actor: user)

      refute_predicate sponsorship.reload, :active?
    end

    test "does not cancel unrelated sponsorship" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      refute_equal @billing_manager, sponsorship.sponsorable

      assert @billing_manager.cancel_sponsorships_from_and_to(@sponsor, actor: @billing_manager)
      assert @sponsor.cancel_sponsorships_from_and_to(@billing_manager, actor: @sponsor)

      assert_predicate sponsorship.reload, :active?,
        "should not have cancelled sponsorship that doesn't involve both of the users"
    end

    test "no-op when given the same user it's called on" do
      assert @sponsor.cancel_sponsorships_from_and_to(@sponsor, actor: @sponsor)
    end

    test "returns false when any sponsorship fails to cancel" do
      Sponsorship.any_instance.stubs(:cancel).returns(Billing::Public::ResultStruct.new(success: false))
      sponsorship = @sponsorships_for_sponsor.first
      other_user = sponsorship.sponsorable

      refute @sponsor.cancel_sponsorships_from_and_to(other_user, actor: @sponsor)
    end

    test "instruments sponsorship cancellation request to Hydro" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      other_user = sponsorship.sponsorable

      assert @sponsor.cancel_sponsorships_from_and_to(other_user, actor: @sponsor, reason: :BLOCKED_USER)

      refute_predicate sponsorship.reload, :active?

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
        sponsorable: Hydro::EntitySerializer.user(other_user),
        reason: :BLOCKED_USER,
        forced: true,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end
  end

  context "#cancel_all_sponsorships" do
    test "cancels all sponsorship from the user" do
      (1..4).each { |_| create(:sponsorship, sponsor: @sponsor) }

      assert @sponsor.cancel_all_sponsorships(actor: User.staff_user, reason: :BLOCKED_USER)

      assert_predicate @sponsor.reload.public_and_private_sponsoring_count, :zero?
    end

    test "no-op when there are no sponsorships to cancel" do
      assert @sponsor.cancel_all_sponsorships(actor: User.staff_user, reason: :BLOCKED_USER)
    end

    test "returns false when any sponsorship fails to cancel" do
      Sponsorship.any_instance.stubs(:cancel).returns(Billing::Public::ResultStruct.new(success: false))

      refute @sponsor.cancel_all_sponsorships(actor: User.staff_user, reason: :BLOCKED_USER)
    end

    test "instruments sponsorship cancellation request to Hydro" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      other_user = sponsorship.sponsorable

      assert @sponsor.cancel_all_sponsorships(actor: User.staff_user, reason: :BLOCKED_USER)

      refute_predicate sponsorship.reload, :active?
      assert_predicate @sponsor.reload.public_and_private_sponsoring_count, :zero?

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
        sponsorable: Hydro::EntitySerializer.user(other_user),
        reason: :BLOCKED_USER,
        forced: true,
      }
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCancelRequest")
      assert_hydro_messages(count: 4, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end
  end

  context "#has_valid_payment_method_for_sponsorships?" do
    test "returns false when sponsorship payment method is PayPal" do
      user = create(:paypal_customer_account).user
      refute_predicate user, :has_valid_payment_method_for_sponsorships?
    end

    test "returns true for Sponsors-invoiced org even when it has a PayPal fallback payment method" do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      assert_predicate org, :sponsors_invoiced?
      create(:paypal_payment_method, customer: org.customer)
      assert_predicate org, :has_valid_payment_method_for_sponsorships?
    end

    test "returns true when sponsorship payment method is delegated to business" do
      business = create(:business, :with_valid_contact_for_billing, :with_credit_card)
      org_sponsor = create(:organization, business: business)
      assert_predicate org_sponsor, :has_valid_payment_method_for_sponsorships?
    end
  end

  context "#set_sponsorship_rollback_notification" do
    test "sets global notice on user" do
      @non_sponsor.set_sponsorship_rollback_notification

      assert_equal :sponsorship_rollback, GlobalNoticeNext.new(viewer: @non_sponsor).current_notice_name
    end
  end

  context "#can_load_sponsorable_dependencies_for?" do
    test "returns false when given nil" do
      refute @sponsor.can_load_sponsorable_dependencies_for?(nil)
    end

    test "returns true when the user is an admin of the given org" do
      assert @org_sponsor_admin.can_load_sponsorable_dependencies_for?(@org_sponsor)
    end

    test "returns true when the user is a billing manager of the given org" do
      assert @billing_manager.can_load_sponsorable_dependencies_for?(@org_sponsor)
    end

    test "returns true when the user belongs to the given org" do
      assert @public_org_member.can_load_sponsorable_dependencies_for?(@org_sponsor)
      assert @private_org_member.can_load_sponsorable_dependencies_for?(@org_sponsor)
    end

    test "returns false when a non-staff user has no connection to the given org" do
      refute @non_sponsor.can_load_sponsorable_dependencies_for?(@org_sponsor)
    end

    test "returns true when a staff user has no connection to the given org" do
      assert @staff.can_load_sponsorable_dependencies_for?(@org_sponsor)
    end

    test "returns false when given another user" do
      refute @org_sponsor_admin.can_load_sponsorable_dependencies_for?(@billing_manager)
    end

    test "returns false when called on an org" do
      refute @org_sponsor.can_load_sponsorable_dependencies_for?(@org_sponsor_admin)
    end
  end

  context "#customer_bill_cycle_day_for_sponsorships" do
    test "returns the sponsors-purpose customer's value if present even when business exists" do
      sponsors_bill_cycle_day = 10
      general_bill_cycle_day = 5
      sponsors_invoiced_enterprise_linked_org = create(:enterprise_linked_org, :sponsors_invoiced)
      sponsors_invoiced_enterprise_linked_org.business.customer.update!(bill_cycle_day: general_bill_cycle_day)
      sponsors_invoiced_enterprise_linked_org.sponsors_customer.update!(bill_cycle_day: sponsors_bill_cycle_day)

      assert_equal sponsors_bill_cycle_day, sponsors_invoiced_enterprise_linked_org
        .customer_bill_cycle_day_for_sponsorships
    end

    test "does not return the business's value if there is a business and no sponsors-purpose customer" do
      @org.update!(business: @business)
      @business.customer.update!(bill_cycle_day: 5)

      assert_equal 0, @org.customer_bill_cycle_day_for_sponsorships
    end

    test "returns the general-purpose customer's value if there's no sponsors-purpose customer" do
      @org.customer = create(:customer, bill_cycle_day: 5)

      assert_nil @org.sponsors_customer, "sponsors_customer should be nil"
      assert_equal @org.customer.bill_cycle_day, @org.customer_bill_cycle_day_for_sponsorships
    end

    test "returns zero when there's no customer" do
      @org.customer = nil

      assert_equal 0, @org.customer_bill_cycle_day_for_sponsorships
    end
  end

  # See tests below for #total_funded_via_github_sponsors as well to verify the dollar amount returned by
  # #async_total_funded_via_github_sponsors stays in sync when an amount is returned at all:
  context "#async_total_funded_via_github_sponsors" do
    test "returns nil when one user views another user's amount" do
      viewers = [@non_sponsor, nil]
      viewers.each do |viewer|
        assert_nil @sponsor.async_total_funded_via_github_sponsors(viewer: viewer).sync,
          "should return nil for viewer without permission when no time range is given"
        assert_nil @sponsor.async_total_funded_via_github_sponsors(viewer: viewer, since_time: 1.week.ago).sync,
          "should still return nil even when since_time is specified"
        assert_nil @sponsor.async_total_funded_via_github_sponsors(
          viewer: viewer, since_time: 1.week.ago, until_time: Time.now,
        ).sync, "should still return nil even when since and until times are specified"
        assert_nil @sponsor.async_total_funded_via_github_sponsors(viewer: viewer, until_time: Time.now).sync,
          "should still return nil even when until_time is specified"
      end
    end

    test "returns a Billing::Money when viewing your own amount" do
      assert_instance_of Billing::Money, @sponsor.async_total_funded_via_github_sponsors(
        viewer: @sponsor,
      ).sync
    end

    test "returns nil when viewing an org's amount by someone neither an org admin nor billing manager" do
      viewers = [@non_sponsor, nil, @public_org_member, @private_org_member]
      viewers.each do |viewer|
        assert_nil @org_sponsor.async_total_funded_via_github_sponsors(viewer: viewer).sync,
          "should return nil for viewer without permission when no time range is given"
        assert_nil @org_sponsor.async_total_funded_via_github_sponsors(viewer: viewer, since_time: 1.week.ago).sync,
          "should still return nil even when since_time is specified"
        assert_nil @org_sponsor.async_total_funded_via_github_sponsors(
          viewer: viewer, since_time: 1.week.ago, until_time: Time.now,
        ).sync, "should still return nil even when since and until times are specified"
        assert_nil @org_sponsor.async_total_funded_via_github_sponsors(viewer: viewer, until_time: Time.now).sync,
          "should still return nil even when until_time is specified"
      end
    end

    test "returns a Billing::Money when viewing an org's amount as an org admin or billing manager" do
      assert_instance_of Billing::Money, @org_sponsor.async_total_funded_via_github_sponsors(
        viewer: @org_sponsor_admin,
      ).sync
      assert_instance_of Billing::Money, @org_sponsor.async_total_funded_via_github_sponsors(
        viewer: @billing_manager,
      ).sync
    end
  end

  context "#total_funded_via_github_sponsors and #async_total_funded_via_github_sponsors" do
    test "returns sum of sponsorship payments from a user with a recurring sponsorship" do
      sponsorship = travel_to(1.month.ago) do
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @sponsor)
      end
      tier = sponsorship.tier

      # This month's payment for the same sponsorship:
      transaction = create(:billing_transaction, user: @sponsor, amount_in_cents: tier.monthly_price_in_cents)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: tier)

      expected_money = Billing::Money.new(tier.monthly_price_in_cents * 2)

      assert_equal expected_money, @sponsor.total_funded_via_github_sponsors
      assert_equal expected_money, @sponsor.async_total_funded_via_github_sponsors(viewer: @sponsor).sync
    end

    test "omits fees" do
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      travel_to Sponsorship::SPONSORS_PUBLIC_RELEASE_DATE
      assert_predicate @org_sponsor, :should_pay_fees_at_sponsorship_payment_time?
      sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @org_sponsor, tier: tier)
      assert_predicate sponsorship, :started_after_sponsors_public_release?
      expected_money = tier.base_price(include_fees: false)

      assert_equal expected_money, @org_sponsor.total_funded_via_github_sponsors
      assert_equal expected_money, @org_sponsor
        .async_total_funded_via_github_sponsors(viewer: @org_sponsor.admin).sync
    end

    test "can be filtered to include sponsorship payments only to particular sponsorables" do
      included_sponsorship1 = create(:sponsorship, :with_billing_transaction_and_line_item,
        sponsor: @org_that_pays, monthly_price_in_cents: 10_00)
      excluded_sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item,
        sponsor: @org_that_pays, monthly_price_in_cents: 8_00)

      # Make a one-time payment to included_sponsorable1 in addition to the recurring sponsorship:
      included_sponsorable1 = included_sponsorship1.sponsorable
      included_sponsorable1_one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: included_sponsorable1.sponsors_listing, monthly_price_in_cents: 11_00)
      included_transaction = create(:billing_transaction, user: @org_that_pays,
        amount_in_cents: included_sponsorable1_one_time_tier.monthly_price_in_cents)
      create(:billing_transaction_line_item, :sponsors, billing_transaction: included_transaction,
        subscribable: included_sponsorable1_one_time_tier)

      included_sponsorship2 = create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @org_that_pays,
        monthly_price_in_cents: 12_00)
      included_sponsorable2 = included_sponsorship2.sponsorable

      create(:stripe_connect_account, sponsors_listing: included_sponsorable2.sponsors_listing)
      included_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org_that_pays,
        sponsors_listing: included_sponsorable2.sponsors_listing, amount_in_cents: 13_00)

      sponsorable_ids = [included_sponsorable1.id, included_sponsorable2.id]
      expected_money = Billing::Money.new(
        included_sponsorship1.monthly_price_in_cents + included_transaction.amount_in_cents +
          included_sponsorship2.monthly_price_in_cents + included_transfer.amount_in_cents,
      )

      assert_equal expected_money, @org_that_pays.total_funded_via_github_sponsors(sponsorable_ids: sponsorable_ids)
      assert_equal expected_money, @org_that_pays.async_total_funded_via_github_sponsors(
        sponsorable_ids: sponsorable_ids,
        viewer: @org_that_pays.admin,
      ).sync
    end

    test "can be filtered to include only transactions made on or after a given time" do
      two_months_ago = 2.months.ago
      sponsorship = travel_to(two_months_ago) do
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @sponsor)
      end
      tier = sponsorship.tier

      last_month = 1.month.ago
      travel_to(last_month) do
        transaction = create(:billing_transaction, user: @sponsor, amount_in_cents: tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: tier)
      end

      # This month's payment for the sponsorship:
      this_month = Time.now
      travel_to(this_month) do
        transaction = create(:billing_transaction, user: @sponsor, amount_in_cents: tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: tier)
      end

      expected_amounts_by_since_time = {
        two_months_ago => tier.monthly_price_in_cents * 3,
        last_month => tier.monthly_price_in_cents * 2,
        this_month => tier.monthly_price_in_cents,
      }
      expected_amounts_by_since_time.each do |since_time, expected_cents|
        expected_money = Billing::Money.new(expected_cents)
        assert_equal expected_money, @sponsor.total_funded_via_github_sponsors(since_time: since_time)
        assert_equal expected_money, @sponsor
          .async_total_funded_via_github_sponsors(viewer: @sponsor, since_time: since_time).sync
      end
    end

    test "can be filtered to include only transactions made before a given time" do
      two_months_ago = 2.months.ago
      sponsorship = travel_to(two_months_ago) do
        create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @sponsor)
      end
      tier = sponsorship.tier

      last_month = 1.month.ago
      travel_to(last_month) do
        transaction = create(:billing_transaction, user: @sponsor, amount_in_cents: tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: tier)
      end

      # This month's payment for the sponsorship:
      this_month = Time.now
      travel_to(this_month) do
        transaction = create(:billing_transaction, user: @sponsor, amount_in_cents: tier.monthly_price_in_cents)
        create(:billing_transaction_line_item, :sponsors, billing_transaction: transaction, subscribable: tier)
      end

      expected_amounts_by_until_time = {
        two_months_ago => 0,
        last_month => tier.monthly_price_in_cents,
        this_month => tier.monthly_price_in_cents * 2,
        1.day.from_now => tier.monthly_price_in_cents * 3,
      }
      expected_amounts_by_until_time.each do |until_time, expected_cents|
        expected_money = Billing::Money.new(expected_cents)
        assert_equal expected_money, @sponsor.total_funded_via_github_sponsors(until_time: until_time)
        assert_equal expected_money, @sponsor
          .async_total_funded_via_github_sponsors(viewer: @sponsor, until_time: until_time).sync
      end
    end

    test "returns $0 when user has never had a sponsorship" do
      assert_equal Billing::Money.zero, @non_sponsor.total_funded_via_github_sponsors
      assert_equal Billing::Money.zero, @non_sponsor.async_total_funded_via_github_sponsors(viewer: @non_sponsor).sync
    end

    test "returns sum of sponsorship payments made by the user across maintainers" do
      sponsorship1, sponsorship2 = create_pair(:sponsorship, :with_billing_transaction_and_line_item,
        sponsor: @sponsor)
      refute_equal sponsorship1.sponsorable_id, sponsorship2.sponsorable_id,
        "need two sponsorships for different maintainers"

      expected_money = Billing::Money.new(sponsorship1.monthly_price_in_cents + sponsorship2.monthly_price_in_cents)

      assert_equal expected_money, @sponsor.total_funded_via_github_sponsors
      assert_equal expected_money, @sponsor.async_total_funded_via_github_sponsors(viewer: @sponsor).sync
    end

    test "returns sum of sponsorships from a linked org" do
      sponsorship = create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @org_that_pays)
      expected_money = Billing::Money.new(sponsorship.monthly_price_in_cents)

      assert_equal expected_money, @org_that_gets_credit.total_funded_via_github_sponsors
      assert_equal expected_money, @org_that_gets_credit.async_total_funded_via_github_sponsors(
        viewer: @org_that_gets_credit.admin,
      ).sync
    end

    test "returns sum of line items and invoiced transfers for invoiced org" do
      line_item = create(:billing_transaction_line_item, :sponsors,
        plan_subscription: @invoiced_org.sponsors_plan_subscription)
      transfer = create(:invoiced_sponsorship_transfer, sponsor: @invoiced_org)
      expected_money = Billing::Money.new(line_item.amount_in_cents + transfer.amount_in_cents)

      assert_equal expected_money, @invoiced_org.total_funded_via_github_sponsors
      assert_equal expected_money, @invoiced_org.async_total_funded_via_github_sponsors(
        viewer: @invoiced_org.admin,
      ).sync
    end

    test "respects since_time when determining which invoiced transfers to include" do
      this_month = Time.now
      last_month = this_month - 1.month

      last_month_transfer = travel_to(last_month) { create(:invoiced_sponsorship_transfer, sponsor: @invoiced_org) }
      this_month_transfer = travel_to(this_month) { create(:invoiced_sponsorship_transfer, sponsor: @invoiced_org) }

      expected_amounts_by_since_time = {
        last_month - 1.hour => last_month_transfer.amount_in_cents + this_month_transfer.amount_in_cents,
        this_month - 1.hour => this_month_transfer.amount_in_cents,
      }

      expected_amounts_by_since_time.each do |since_time, expected_cents|
        expected_money = Billing::Money.new(expected_cents)

        actual_money = @invoiced_org.total_funded_via_github_sponsors(since_time: since_time)

        assert_equal expected_money, actual_money,
          "expected amount paid since #{since_time} to be #{expected_money.format}, got #{actual_money.format}"
        assert_equal expected_money, @invoiced_org.async_total_funded_via_github_sponsors(
          viewer: @invoiced_org.admin, since_time: since_time,
        ).sync, "expected async method result to match synchronous method result"
      end
    end

    test "respects until_time when determining which invoiced transfers to include" do
      this_month = Time.now
      last_month = this_month - 1.month
      future_time = this_month + 1.day

      last_month_transfer = travel_to(last_month) do
        create(:invoiced_sponsorship_transfer, sponsor: @invoiced_org, amount_in_cents: 1_000_00)
      end
      this_month_transfer = travel_to(this_month) do
        create(:invoiced_sponsorship_transfer, sponsor: @invoiced_org, amount_in_cents: 2_500_00)
      end

      expected_amounts_by_until_time = {
        last_month - 1.hour => 0,
        this_month - 1.hour => last_month_transfer.amount_in_cents,
        future_time - 1.hour => last_month_transfer.amount_in_cents + this_month_transfer.amount_in_cents
      }

      expected_amounts_by_until_time.each do |until_time, expected_cents|
        expected_money = Billing::Money.new(expected_cents)

        actual_money = @invoiced_org.total_funded_via_github_sponsors(until_time: until_time)

        assert_equal expected_money, actual_money,
          "expected amount paid up to #{until_time} to be #{expected_money.format}, got #{actual_money.format}"
        assert_equal expected_money, @invoiced_org.async_total_funded_via_github_sponsors(
          viewer: @invoiced_org.admin, until_time: until_time,
        ).sync, "expected async method result to match synchronous method result"
      end
    end

    test "includes past invoiced line items even if organization is no longer invoiced" do
      line_item = create(:billing_transaction_line_item, :sponsors,
        plan_subscription: @invoiced_org.sponsors_plan_subscription)
      transfer = create(:invoiced_sponsorship_transfer, sponsor: @invoiced_org)

      @invoiced_org.sponsors_customer.delete

      # Create a regular sponsorship not using a Sponsors-specific plan subscription:
      regular_plan_sub = create(:billing_plan_subscription, user: @invoiced_org)
      sponsorship = create(:sponsorship, sponsor: @invoiced_org)
      transaction = create(:billing_transaction, user: @invoiced_org,
        amount_in_cents: sponsorship.monthly_price_in_cents)
      create(:billing_transaction_line_item, :sponsors, plan_subscription: regular_plan_sub,
        billing_transaction: transaction, subscribable: sponsorship.tier)

      expected_money = Billing::Money.new(
        line_item.amount_in_cents + transfer.amount_in_cents + sponsorship.monthly_price_in_cents,
      )

      assert_equal expected_money, @invoiced_org.total_funded_via_github_sponsors,
        "expected Zuora-based invoiced sponsorship ($#{line_item.amount_in_cents / 100}) + " \
        "old-style non-Zuora-based invoiced sponsorship ($#{transfer.amount_in_cents / 100}) + " \
        "regular sponsorship ($#{sponsorship.monthly_price_in_cents / 100})"
      assert_equal expected_money, @invoiced_org.async_total_funded_via_github_sponsors(
        viewer: @invoiced_org.admin,
      ).sync
    end
  end

  context "#public_sponsors_count" do
    test "returns count of active, public sponsorships where the user is the maintainer being sponsored" do
      sponsorship = create(:sponsorship)
      assert_equal 0, sponsorship.sponsor.public_sponsors_count

      sponsorable = sponsorship.sponsorable
      assert_equal 1, sponsorable.public_sponsors_count

      create(:sponsorship, :private, sponsorable: sponsorable)
      assert_equal 1, sponsorable.reload.public_sponsors_count, "should not change with new private sponsorship"

      create(:sponsorship, :inactive, sponsorable: sponsorable)
      assert_equal 1, sponsorable.reload.public_sponsors_count, "should not change with new inactive sponsorship"
    end
  end

  context "#sponsoring_count" do
    if GitHub.sponsors_enabled?
      test "returns public active count when include_private=false" do
        sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons,
        )
        4.times { create(:sponsorship, :public, sponsor: sponsor) }
        create(:sponsorship, :public, :inactive, sponsor: sponsor)

        assert_equal 4, sponsor.sponsoring_count(include_private: false)
        assert_equal 1, sponsor.inactive_public_sponsoring_count
      end

      test "returns public/private active count when include_private=true" do
        sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons,
        )
        4.times { create(:sponsorship, :public, sponsor: sponsor) }
        create(:sponsorship, :public, :inactive, sponsor: sponsor)
        4.times { create(:sponsorship, :private, sponsor: sponsor) }
        create(:sponsorship, :private, :inactive, sponsor: sponsor)

        assert_equal 8, sponsor.sponsoring_count(include_private: true)
        assert_equal 1, sponsor.inactive_public_sponsoring_count
        assert_equal 1, sponsor.sponsorships_as_sponsor.inactive.privacy_private.size
      end

      test "returns 0 when user does not have any sponsorhips record" do
        user = create(:user)
        assert_equal 0, user.sponsoring_count(include_private: true)
        assert_equal 0, user.sponsoring_count(include_private: false)
      end
    else
      test "returns 0 when Sponsors is disabled" do
        user = create(:user)
        assert_equal 0, user.sponsoring_count(include_private: true)
        assert_equal 0, user.sponsoring_count(include_private: false)
      end
    end
  end

  context "#public_and_private_sponsors_count" do
    test "returns count of active sponsorships where the user is the maintainer being sponsored" do
      sponsorship = create(:sponsorship)
      assert_equal 0, sponsorship.sponsor.public_and_private_sponsors_count

      sponsorable = sponsorship.sponsorable
      assert_equal 1, sponsorable.public_and_private_sponsors_count

      create(:sponsorship, :private, sponsorable: sponsorable)
      assert_equal 2, sponsorable.reload.public_and_private_sponsors_count,
        "should change with new private sponsorship"

      create(:sponsorship, :inactive, sponsorable: sponsorable)
      assert_equal 2, sponsorable.reload.public_and_private_sponsors_count,
        "should not change with new inactive sponsorship"
    end
  end

  context "#sponsorship_as_sponsor_for and #async_sponsorship_as_sponsor_for" do
    test "returns inactive sponsorship of the given user" do
      sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable)
      sponsor = sponsorship.sponsor

      assert_equal sponsorship, sponsor.sponsorship_as_sponsor_for(@sponsorable)
      assert_equal sponsorship, sponsor.async_sponsorship_as_sponsor_for(@sponsorable).sync
    end

    test "returns active sponsorship of the given user" do
      assert_predicate @sponsorship1, :active?, "need an active sponsorship"
      sponsor = @sponsorship1.sponsor
      sponsorable = @sponsorship1.sponsorable

      assert_equal @sponsorship1, sponsor.sponsorship_as_sponsor_for(sponsorable)
      assert_equal @sponsorship1, sponsor.async_sponsorship_as_sponsor_for(sponsorable).sync
    end

    test "returns nil when given a non-sponsorable user" do
      assert_nil @non_sponsor.sponsors_listing, "need a user without a Sponsors listing"

      assert_nil @sponsor.sponsorship_as_sponsor_for(@non_sponsor)
      assert_nil @sponsor.async_sponsorship_as_sponsor_for(@non_sponsor).sync
    end

    test "returns sponsorship of the given user when called on an org with a linked org" do
      sponsorship = create(:sponsorship, sponsor: @org_that_pays, sponsorable: @sponsorable)

      assert_equal sponsorship, @org_that_gets_credit.sponsorship_as_sponsor_for(@sponsorable)
      assert_equal sponsorship, @org_that_gets_credit.async_sponsorship_as_sponsor_for(@sponsorable).sync
    end

    test "returns nil when the user has never sponsoring anyone" do
      assert_empty @non_sponsor.sponsorships_as_sponsor, "need a user who has never sponsored"

      assert_nil @non_sponsor.sponsorship_as_sponsor_for(@sponsorable)
      assert_nil @non_sponsor.async_sponsorship_as_sponsor_for(@sponsorable).sync
    end

    test "returns nil when user has never sponsored the specified user" do
      refute_empty @sponsor.sponsorships_as_sponsor, "need a user who has sponsored before"
      random_maintainer = create(:user, :sponsorable)

      assert_nil @sponsor.sponsorship_as_sponsor_for(random_maintainer)
      assert_nil @sponsor.async_sponsorship_as_sponsor_for(random_maintainer).sync
    end
  end

  context "#inactive_public_sponsoring_count" do
    test "returns count of inactive, public sponsorships where the user is the funder" do
      sponsorship = create(:sponsorship, :inactive)
      assert_equal 0, sponsorship.sponsorable.inactive_public_sponsoring_count

      sponsor = sponsorship.sponsor
      assert_equal 1, sponsor.inactive_public_sponsoring_count

      create(:sponsorship, :private, :inactive, sponsor: sponsor)
      assert_equal 1, sponsor.reload.inactive_public_sponsoring_count,
        "should not change with new private sponsorship"

      create(:sponsorship, sponsor: sponsor)
      assert_equal 1, sponsor.reload.inactive_public_sponsoring_count, "should not change with new active sponsorship"
    end

    test "does not include inactive unpaid sponsorships in sponsoring count" do
      sponsorship = create(:sponsorship, :inactive)

      sponsor = sponsorship.sponsor
      assert_equal 1, sponsor.inactive_public_sponsoring_count

      create(:sponsorship, :inactive, :unpaid, sponsor: sponsor)
      assert_equal 1, sponsor.reload.inactive_public_sponsoring_count,
        "should not change with new inactive, unpaid sponsorship"
    end
  end

  context "#total_direct_dependencies_sponsorable" do
    if GitHub.sponsors_enabled?
      test "counts how many sponsorable direct dependencies the user has that are in repos the viewer can know about" do
        dependency_from_public_repo = create(:repository_sponsorable, :owner).repository
        dependency_from_private_repo = create(:repository_sponsorable, :owner).repository

        # Additional sponsorables for one of the dependencies, to show that we count dependencies and not
        # sponsorables:
        create(:repository_preferred_file, :funding, repository: dependency_from_public_repo)
        create_pair(:repository_sponsorable, :funding_file, repository: dependency_from_public_repo)

        # Once for `@non_sponsor` viewer, once for anonymous viewer:
        fake_public_only_response = stub(ok?: true, value!: { dependencies: [dependency_from_public_repo.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).twice.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_public_only_response))

        # Once for `@sponsor` viewer:
        fake_public_and_private_response = stub(ok?: true, value!: {
          dependencies: [dependency_from_public_repo.id, dependency_from_private_repo.id],
        })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_priv_repo.id, @sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_public_and_private_response))

        assert_equal 2, @sponsor.total_direct_dependencies_sponsorable(viewer: @sponsor)
        assert_equal 1, @sponsor.total_direct_dependencies_sponsorable(viewer: @non_sponsor)
        assert_equal 1, @sponsor.total_direct_dependencies_sponsorable(viewer: nil)
      end
    else
      test "returns 0 regardless of viewer when Sponsors is disabled" do
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).never

        assert_equal 0, @sponsor.total_direct_dependencies_sponsorable(viewer: @sponsor)
        assert_equal 0, @sponsor.total_direct_dependencies_sponsorable(viewer: nil)
        assert_equal 0, @sponsor.total_direct_dependencies_sponsorable(viewer: @non_sponsor)
      end
    end
  end

  context "#inactive_public_sponsors_count" do
    test "returns count of inactive, public sponsorships where the user is the maintainer being sponsored" do
      sponsorship = create(:sponsorship, :inactive)
      assert_equal 0, sponsorship.sponsor.inactive_public_sponsors_count

      sponsorable = sponsorship.sponsorable
      assert_equal 1, sponsorable.inactive_public_sponsors_count

      create(:sponsorship, :private, :inactive, sponsorable: sponsorable)
      assert_equal 1, sponsorable.reload.inactive_public_sponsors_count,
        "should not change with new private sponsorship"

      create(:sponsorship, sponsorable: sponsorable)
      assert_equal 1, sponsorable.reload.inactive_public_sponsors_count,
        "should not change with new active sponsorship"
    end
  end

  context "#direct_dependency_sponsorable_ids_by_dependency_id" do
    if GitHub.sponsors_enabled?
      test "returns unique sponsorable IDs associated with each of the user's dependencies" do
        sponsorable1, sponsorable2 = create_pair(:user, :sponsorable)
        non_sponsorable = create(:user)

        dependency1 = create(:repository_sponsorable, :owner, sponsorable: sponsorable1).repository
        dependency2 = create(:repository_sponsorable, :global_funding_file, sponsorable: sponsorable1).repository
        dependency3 = create(:repository_sponsorable, :funding_file, sponsorable: sponsorable2).repository
        dependency4 = create(:repository, owner: non_sponsorable)
        dependency_ids = [dependency1.id, dependency2.id, dependency3.id, dependency4.id]

        fake_response = stub(ok?: true, value!: { dependencies: dependency_ids })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_priv_repo.id, @sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        result = @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @sponsor)

        assert_equal({
          dependency1.id => [sponsorable1.id],
          dependency2.id => [sponsorable1.id],
          dependency3.id => [sponsorable2.id],
        }, result)
      end

      test "includes each sponsorable for a repository" do
        sponsorable1, sponsorable2 = create_pair(:user, :sponsorable)

        dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable1).repository
        create(:repository_preferred_file, :funding, repository: dependency)
        create(:repository_sponsorable, :funding_file, sponsorable: sponsorable2, repository: dependency)

        fake_response = stub(ok?: true, value!: { dependencies: [dependency.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_priv_repo.id, @sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        result = @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @sponsor)

        assert_equal [dependency.id], result.keys
        assert_same_elements [sponsorable1.id, sponsorable2.id], result[dependency.id]
      end

      test "memoizes results for each viewer" do
        dependency_from_public_repo = create(:repository_sponsorable, :owner).repository
        dependency_from_private_repo = create(:repository_sponsorable, :owner).repository

        expected_dg_api_params = {
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
        }

        # Once for `@non_sponsor` viewer, once for anonymous viewer:
        fake_public_only_response = stub(ok?: true, value!: { dependencies: [dependency_from_public_repo.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).twice.with(equals(
          **expected_dg_api_params.merge(repository_ids: [@sponsor_pub_repo.id]),
        )).returns(Promise.resolve(fake_public_only_response))

        # Once for `@sponsor` viewer:
        fake_public_and_private_response = stub(ok?: true, value!: {
          dependencies: [dependency_from_public_repo.id, dependency_from_private_repo.id],
        })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          **expected_dg_api_params.merge(
            repository_ids: [@sponsor_priv_repo.id, @sponsor_pub_repo.id],
          ),
        )).returns(Promise.resolve(fake_public_and_private_response))

        result_for_non_sponsor = @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @non_sponsor)
        assert_no_queries do
          assert_equal result_for_non_sponsor,
            @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @non_sponsor)
        end

        result_for_sponsor = @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @sponsor)
        assert_no_queries do
          assert_equal result_for_sponsor,
            @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @sponsor)
        end

        result_for_anon = @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: nil)
        assert_no_queries do
          assert_equal result_for_anon,
            @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: nil)
        end
      end

      test "only checks the user's public repositories for dependencies when viewed by someone else" do
        fake_response = stub(ok?: true, value!: { dependencies: [] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @non_sponsor)
      end

      test "only checks the org's public repositories for dependencies when viewed by non-member" do
        fake_response = stub(ok?: true, value!: { dependencies: [] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org_sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        @org_sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @non_sponsor)
      end

      test "only checks the org's public repositories for dependencies when viewed by an org billing manager" do
        billing_manager = create(:user)
        @org_sponsor.billing.add_manager(billing_manager, actor: @org_sponsor_admin)

        fake_response = stub(ok?: true, value!: { dependencies: [] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org_sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        @org_sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: billing_manager)
      end

      test "checks the org's private and public repositories for dependencies when viewed by an org admin" do
        fake_response = stub(ok?: true, value!: { dependencies: [] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org_sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_sponsor_priv_repo.id, @org_sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        @org_sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @org_sponsor_admin)
      end
    else
      test "returns an empty hash when Sponsors is disabled" do
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).never
        assert_equal({}, @sponsor.direct_dependency_sponsorable_ids_by_dependency_id(viewer: @sponsor))
      end
    end
  end

  context "#inactive_public_and_private_sponsors_count" do
    test "returns count of inactive sponsorships where the user is the maintainer being sponsored" do
      sponsorship = create(:sponsorship, :inactive, :private)
      assert_equal 0, sponsorship.sponsor.inactive_public_and_private_sponsors_count

      sponsorable = sponsorship.sponsorable
      assert_equal 1, sponsorable.inactive_public_and_private_sponsors_count

      create(:sponsorship, :private, :inactive, sponsorable: sponsorable)
      assert_equal 2, sponsorable.reload.inactive_public_and_private_sponsors_count,
        "should change with new private sponsorship"

      create(:sponsorship, sponsorable: sponsorable)
      assert_equal 2, sponsorable.reload.inactive_public_and_private_sponsors_count,
        "should not change with new active sponsorship"

      create(:sponsorship, :inactive, sponsorable: sponsorable)
      assert_equal 3, sponsorable.reload.inactive_public_and_private_sponsors_count,
        "should change with new public sponsorship that is inactive"
    end
  end

  context "#repository_ids_to_check_for_sponsorable_dependencies" do
    test "returns only public repository IDs when viewer can't access any of the user's private repos" do
      assert_equal [@sponsor_pub_repo.id],
        @sponsor.repository_ids_to_check_for_sponsorable_dependencies(viewer: @non_sponsor)
      assert_equal [@sponsor_pub_repo.id],
        @sponsor.repository_ids_to_check_for_sponsorable_dependencies(viewer: nil)
    end

    test "returns public and private repository IDs when viewer is the user" do
      assert_equal [@sponsor_priv_repo.id, @sponsor_pub_repo.id],
        @sponsor.repository_ids_to_check_for_sponsorable_dependencies(viewer: @sponsor)
    end

    test "returns public and private repository IDs the viewer can access" do
      other_private_repo = create(:private_repository, owner: @sponsor)
      other_private_repo.add_member(@non_sponsor)
      assert_equal [other_private_repo.id, @sponsor_pub_repo.id],
        @sponsor.repository_ids_to_check_for_sponsorable_dependencies(viewer: @non_sponsor)
    end

    test "returns public and private repository IDs when viewer is the org's admin" do
      assert_equal [@org_sponsor_priv_repo.id, @org_sponsor_pub_repo.id],
        @org_sponsor.repository_ids_to_check_for_sponsorable_dependencies(viewer: @org_sponsor_admin)
    end

    test "limits repositories to just the top ones when user has more than the limit" do
      Repository::OwnerDependenciesLoader.stub_const(:MAX_REPOSITORY_IDS, 1) do
        assert_equal [@sponsor_priv_repo.id],
          @sponsor.repository_ids_to_check_for_sponsorable_dependencies(viewer: @sponsor)
      end
    end
  end

  context "#inactive_public_and_private_sponsoring_count" do
    test "returns count of inactive, public sponsorships where the user is the funder" do
      sponsorship = create(:sponsorship, :inactive)
      assert_equal 0, sponsorship.sponsorable.inactive_public_and_private_sponsoring_count

      sponsor = sponsorship.sponsor
      assert_equal 1, sponsor.inactive_public_and_private_sponsoring_count

      create(:sponsorship, :private, :inactive, sponsor: sponsor)
      assert_equal 2, sponsor.reload.inactive_public_and_private_sponsoring_count,
        "should change with new private sponsorship that is inactive"

      create(:sponsorship, sponsor: sponsor)
      assert_equal 2, sponsor.reload.inactive_public_and_private_sponsoring_count,
        "should not change with new active sponsorship"

      create(:sponsorship, :inactive, sponsor: sponsor)
      assert_equal 3, sponsor.reload.inactive_public_and_private_sponsoring_count,
        "should change with new public sponsorship that is inactive"
    end

    test "does not include unpaid inactive sponsorings in count" do
      sponsorship = create(:sponsorship, :inactive)
      sponsor = sponsorship.sponsor

      assert_equal 1, sponsor.inactive_public_and_private_sponsoring_count

      create(:sponsorship, :inactive, :unpaid, sponsor: sponsor)
      assert_equal 1, sponsor.reload.inactive_public_and_private_sponsoring_count,
        "should not change with new inactive, unpaid sponsorship"
    end
  end

  context "#total_direct_dependencies_sponsored" do
    if GitHub.sponsors_enabled?
      test "returns 0 regardless of viewer when user has no sponsorships" do
        assert_equal 0, @non_sponsor.total_direct_dependencies_sponsored(viewer: nil), "0 for anon viewer"
        assert_equal 0, @non_sponsor.total_direct_dependencies_sponsored(viewer: @non_sponsor), "0 for themselves"
        assert_equal 0, @non_sponsor.total_direct_dependencies_sponsored(viewer: @sponsor), "0 for other viewer"
      end

      test "returns 0 regardless of viewer when user has only inactive sponsorships" do
        inactive_sponsorship = create(:sponsorship, :inactive)
        inactive_sponsor = inactive_sponsorship.sponsor
        inactive_private_sponsorship = create(:sponsorship, :private, :inactive, sponsor: inactive_sponsor)

        assert_equal 0, inactive_sponsor.total_direct_dependencies_sponsored(viewer: nil), "0 for anon viewer"
        assert_equal 0, inactive_sponsor.total_direct_dependencies_sponsored(viewer: inactive_sponsor), "0 for self"
        assert_equal 0, inactive_sponsor.total_direct_dependencies_sponsored(viewer: @sponsor), "0 for other viewer"
      end

      test "returns 0 when user has no direct dependencies" do
        fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
          data: { repositoryOwnerDependencies: { dependencies: [] } },
        })
        DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

        assert_equal 0, @sponsor.total_direct_dependencies_sponsored(viewer: @sponsor)
      end

      test "checks user's public and private repos for publicly and privately sponsored dependencies when the user themselves is the viewer" do
        pub_sponsorship1, pub_sponsorship2 = @sponsorships_for_sponsor.first(2)

        dependency1 = create(:repository_sponsorable, :owner, sponsorable: pub_sponsorship1.sponsorable).repository
        dependency2 = create(:repository_sponsorable, :owner, sponsorable: pub_sponsorship1.sponsorable).repository
        dependency3 = create(:repository_sponsorable, :owner, sponsorable: pub_sponsorship2.sponsorable).repository
        dependency4 = create(:repository_sponsorable, :owner).repository

        # Private sponsorship should be counted:
        create(:sponsorship, :private, sponsor: @sponsor, sponsorable: dependency4.owner)

        fake_response = stub(ok?: true, value!: {
          dependencies: [dependency1.id, dependency2.id, dependency3.id, dependency4.id],
        })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_priv_repo.id, @sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 4, @sponsor.total_direct_dependencies_sponsored(viewer: @sponsor),
          "should return how many dependencies are sponsored, not how many unique people are sponsored"
      end

      test "checks user's public repos for publicly sponsored dependencies for anonymous viewer" do
        public_sponsorship = @sponsorships_for_sponsor[0]
        dependency1 = create(:repository_sponsorable, :owner, sponsorable: public_sponsorship.sponsorable).repository
        dependency2 = create(:repository_sponsorable, :owner).repository
        dependency3 = create(:repository_sponsorable, :owner).repository

        # Private sponsorships shouldn't be counted:
        create(:sponsorship, :private, sponsor: @sponsor, sponsorable: dependency2.owner)
        create(:sponsorship, :private, sponsor: @sponsor, sponsorable: dependency3.owner)

        fake_response = stub(ok?: true, value!: { dependencies: [dependency1.id, dependency2.id, dependency3.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 1, @sponsor.total_direct_dependencies_sponsored(viewer: nil),
          "should have counted just the user's public sponsorship for dependency1's owner"
      end

      test "checks user's public repos for publicly sponsored dependencies for viewer other than the user" do
        public_sponsorship = @sponsorships_for_sponsor[0]
        dependency1 = create(:repository_sponsorable, :owner, sponsorable: public_sponsorship.sponsorable).repository
        dependency2 = create(:repository_sponsorable, :owner).repository
        dependency3 = create(:repository_sponsorable, :owner).repository

        # Private sponsorships shouldn't be counted:
        create(:sponsorship, :private, sponsor: @sponsor, sponsorable: dependency2.owner)
        create(:sponsorship, :private, sponsor: @sponsor, sponsorable: dependency3.owner)

        fake_response = stub(ok?: true, value!: { dependencies: [dependency1.id, dependency2.id, dependency3.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 1, @sponsor.total_direct_dependencies_sponsored(viewer: @non_sponsor),
          "should have counted just the user's public sponsorship for dependency1's owner"
      end

      test "checks org's public repos for publicly sponsored dependencies for anonymous viewer" do
        dependency1 = create(:repository_sponsorable, :owner,
          sponsorable: @sponsorship_with_org_sponsor.sponsorable).repository
        dependency2 = create(:repository_sponsorable, :owner).repository
        dependency3 = create(:repository_sponsorable, :owner).repository

        # Private sponsorships shouldn't be counted:
        create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: dependency2.owner)
        create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: dependency3.owner)

        fake_response = stub(ok?: true, value!: { dependencies: [dependency1.id, dependency2.id, dependency3.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org_sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 1, @org_sponsor.total_direct_dependencies_sponsored(viewer: nil),
          "should have counted just the org's public sponsorship for dependency1's owner"
      end

      test "checks org's public and private repos for publicly and privately sponsored dependencies for org owner viewer" do
        dependency1 = create(:repository_sponsorable, :owner,
          sponsorable: @sponsorship_with_org_sponsor.sponsorable).repository
        dependency2 = create(:repository_sponsorable, :owner).repository
        dependency3 = create(:repository_sponsorable, :owner).repository

        # Private sponsorships should be counted because org admin can see them:
        create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: dependency2.owner)
        create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: dependency3.owner)

        fake_response = stub(ok?: true, value!: { dependencies: [dependency1.id, dependency2.id, dependency3.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org_sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_sponsor_priv_repo.id, @org_sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 3, @org_sponsor.total_direct_dependencies_sponsored(viewer: @org_sponsor_admin)
      end

      test "checks org's public repos for publicly and privately sponsored dependencies for org billing manager viewer" do
        dependency1 = create(:repository_sponsorable, :owner,
          sponsorable: @sponsorship_with_org_sponsor.sponsorable).repository
        dependency2 = create(:repository_sponsorable, :owner).repository

        # Private sponsorship should be counted because org billing manager can see them:
        create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: dependency2.owner)

        fake_response = stub(ok?: true, value!: { dependencies: [dependency1.id, dependency2.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org_sponsor.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_sponsor_pub_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 2, @org_sponsor.total_direct_dependencies_sponsored(viewer: @billing_manager)
      end
    else
      test "returns 0 when Sponsors is disabled" do
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).never
        assert_equal 0, @sponsor.total_direct_dependencies_sponsored(viewer: @sponsor)
      end
    end
  end

  context ".sort_by_sponsor_count" do
    test "sorts the given list of users so that those with the fewest sponsors, public and private, are first" do
      user_with_1 = create(:user_metadata, sponsors_public_and_private_count: 1).user
      user_with_0 = create(:user_metadata, sponsors_public_and_private_count: 0).user
      user_with_2 = create(:user_metadata, sponsors_public_and_private_count: 2).user

      result = User.sort_by_sponsor_count([user_with_1, user_with_0, user_with_2])

      assert_equal [user_with_0, user_with_1, user_with_2], result
    end

    test "returns given list in same order when none of the users have any sponsors" do
      user_c, user_a, user_b = create_list(:user, 3, :sponsorable)
      users = [user_a, user_c, user_b]

      result = User.sort_by_sponsor_count(users)

      assert_equal users, result
    end
  end

  context ".sort_by_sponsors_profile_publish_date" do
    test "sorts the given list of users so that those who got an approved Sponsors listing earliest are first" do
      middle_user = travel_to(1.month.ago) { create(:user, :sponsorable) }
      old_user = travel_to(1.year.ago) { create(:user, :sponsorable) }
      new_user = create(:user, :sponsorable)
      users = [middle_user, old_user, new_user]

      result = User.sort_by_sponsors_profile_publish_date(users)

      assert_equal [old_user, middle_user, new_user], result
    end

    test "puts users without an approved Sponsors listing last" do
      middle_user = travel_to(1.month.ago) { create(:user, :sponsorable) }
      old_non_sponsorable_user = travel_to(1.year.ago) { create(:user) }
      new_user = create(:user, :sponsorable)
      users = [middle_user, old_non_sponsorable_user, new_user]

      result = User.sort_by_sponsors_profile_publish_date(users)

      assert_equal [middle_user, new_user, old_non_sponsorable_user], result
    end

    test "returns given list in unchanged order when none of the users have an approved Sponsors listing" do
      middle_non_sponsorable_user = travel_to(1.month.ago) { create(:user) }
      old_non_sponsorable_user = travel_to(1.year.ago) { create(:user) }
      new_non_sponsorable_user = create(:user)
      users = [middle_non_sponsorable_user, old_non_sponsorable_user, new_non_sponsorable_user]

      result = User.sort_by_sponsors_profile_publish_date(users)

      assert_equal users, result
    end
  end

  context "repository_sponsorables association" do
    test "destroys repo sponsorable records when sponsorable is destroyed" do
      repo_sponsorable = create(:repository_sponsorable, sponsorable: @org)

      assert_difference(-> { RepositorySponsorable.count }, -1) do
        @org.destroy!
      end

      refute RepositorySponsorable.exists?(repo_sponsorable.id)
    end
  end

  context "#sponsors_invoiced?" do
    test "false for users" do
      assert_predicate @sponsor, :user?, "need a user for this test"
      refute_predicate @sponsor, :sponsors_invoiced?
    end

    test "false when the org doesn't have a sponsorship-specific Zuora account" do
      invoiced_org = build(:invoiced_organization)
      assert_nil invoiced_org.sponsors_customer
      refute_predicate invoiced_org, :sponsors_invoiced?
    end

    test "false when sponsorship-specific Zuora account id is blank" do
      invoiced_org = build(:invoiced_organization, :sponsors_invoiced)
      refute_nil invoiced_org.sponsors_customer
      invoiced_org.sponsors_customer.update_column(:zuora_account_id, "")
      refute_predicate invoiced_org, :sponsors_invoiced?
    end

    test "true for invoiced org with active sponsorship-specific Zuora account", skip_enterprise: true do
      invoiced_org = build(:invoiced_organization, :sponsors_invoiced)
      refute_nil invoiced_org.sponsors_customer
      assert_predicate invoiced_org, :sponsors_invoiced?
    end

    unless GitHub.billing_enabled?
      test "false when billing is disabled" do
        invoiced_org = build(:invoiced_organization, :sponsors_invoiced)
        refute_predicate invoiced_org, :sponsors_invoiced?
      end
    end

    unless GitHub.sponsors_enabled?
      test "false when Sponsors is disabled" do
        invoiced_org = build(:invoiced_organization, :sponsors_invoiced)
        refute_predicate invoiced_org, :sponsors_invoiced?
      end
    end
  end

  context "#can_switch_to_sponsors_invoicing?" do
    test "true for credit card org" do
      cc_org = build(:credit_card_organization)
      assert_predicate cc_org, :can_switch_to_sponsors_invoicing?
    end

    test "false for already Sponsors-invoiced org" do
      invoiced_org = build(:invoiced_organization, :sponsors_invoiced)
      refute_predicate invoiced_org, :can_switch_to_sponsors_invoicing?
    end

    test "false for user" do
      user = build(:user)
      refute_predicate user, :can_switch_to_sponsors_invoicing?
    end
  end

  context "#tier_subscription_counts" do
    test "includes count of active sponsorships for each tier" do
      unused_tier = create(:sponsors_tier, sponsors_listing: @sponsors_listing)

      result = @sponsorable.tier_subscription_counts

      assert_equal 0, result[unused_tier.id]
      assert_equal 3, result[@sponsors_listing.default_tier.id]
    end

    test "includes count of active sponsorships for each custom tier price point, indexed by earliest custom tier at the price point" do
      custom_tier1 = create(:sponsors_tier, :custom, sponsors_listing: @sponsors_listing)
      create(:sponsorship, tier: custom_tier1, sponsor: custom_tier1.creator)
      custom_tier2 = create(:sponsors_tier, :custom, sponsors_listing: @sponsors_listing,
        monthly_price_in_cents: custom_tier1.monthly_price_in_cents)
      create(:sponsorship, tier: custom_tier2, sponsor: custom_tier2.creator)
      custom_tier3 = create(:sponsors_tier, :custom, sponsors_listing: @sponsors_listing)
      create(:sponsorship, tier: custom_tier3, sponsor: custom_tier3.creator)

      result = @sponsorable.tier_subscription_counts

      assert_equal 3, result[@sponsors_listing.default_tier.id]
      assert_equal 2, result[custom_tier1.id]
      refute result.key?(custom_tier2.id),
        "should not have a key for custom tier at the same price as another " \
        "custom tier with a lower ID"
      assert_equal 1, result[custom_tier3.id]
    end

    test "does not include expired sponsorship for a one-time published tier" do
      create(:sponsorship, :expired, tier: @one_time_tier)
      result = @sponsorable.tier_subscription_counts
      assert_equal 0, result[@one_time_tier.id]
    end

    test "does not include expired sponsorship for a one-time custom tier" do
      custom_tier = create(:sponsors_tier, :custom, :one_time,
        sponsors_listing: @sponsors_listing)
      create(:sponsorship, :expired, tier: custom_tier, sponsor: custom_tier.creator)

      result = @sponsorable.tier_subscription_counts

      assert_equal 0, result[custom_tier.id]
    end

    test "includes recent sponsorship for a one-time published tier" do
      create(:sponsorship, tier: @one_time_tier)
      result = @sponsorable.tier_subscription_counts
      assert_equal 1, result[@one_time_tier.id]
    end

    test "includes recent sponsorship for a one-time custom tier" do
      custom_tier = create(:sponsors_tier, :custom, :one_time,
        sponsors_listing: @sponsors_listing)
      create(:sponsorship, tier: custom_tier, sponsor: custom_tier.creator)

      result = @sponsorable.tier_subscription_counts

      assert_equal 1, result[custom_tier.id]
    end
  end

  context "#sponsors_stripe_transfer_account_id" do
    test "returns account ID for listing's Stripe" do
      account = create(:stripe_connect_account, sponsors_listing: @sponsors_listing)
      assert_equal account.stripe_account_id, @sponsorable.sponsors_stripe_transfer_account_id
    end

    test "returns parent listing's account ID" do
      sponsorable = @child_listing.sponsorable
      assert_equal @fiscal_stripe.stripe_account_id,
        sponsorable.sponsors_stripe_transfer_account_id
    end
  end

  context "#uses_sponsors_fiscal_host?" do
    test "true when sponsorable uses a fiscal host" do
      assert_predicate @child_listing.sponsorable, :uses_sponsors_fiscal_host?
    end

    test "false when user does not have a Sponsors listing" do
      refute_predicate @non_sponsor, :uses_sponsors_fiscal_host?
    end

    test "false when sponsorable does not use a fiscal host" do
      refute_predicate @sponsorable, :uses_sponsors_fiscal_host?
    end
  end

  context "#possible_sponsors_emails" do
    test "returns an empty scope for organization" do
      org = create(:organization)
      email = create(:user_email, :verified, user: org)

      assert_empty org.reload.possible_sponsors_emails
    end

    test "returns verified emails if sponsorable is user" do
      user = create(:user)
      verified_email = create(:user_email, :verified, user: user)
      unverified_email = create(:user_email, user: user)

      result = user.reload.possible_sponsors_emails

      assert_includes result, verified_email
      refute_includes result, unverified_email
    end
  end

  context "#sponsors_billing_country" do
    test "returns the billing country if the user has a Sponsors listing" do
      refute_nil @sponsorable.sponsors_listing.billing_country

      assert_equal(
        @sponsorable.sponsors_listing.billing_country,
        @sponsorable.sponsors_billing_country,
      )
    end

    test "returns nil if the user has no Sponsors listing" do
      assert_nil @non_sponsor.sponsors_listing
      assert_nil @non_sponsor.sponsors_billing_country
    end
  end

  context "#sponsors_country_of_residence" do
    test "returns the country of residence if the user has a Sponsors listing" do
      refute_nil @sponsorable.sponsors_listing
      refute_nil @sponsorable.sponsors_listing.country_of_residence

      assert_equal(
        @sponsorable.sponsors_listing.country_of_residence,
        @sponsorable.sponsors_country_of_residence,
      )
    end

    test "returns nil if the user has no Sponsors listing" do
      assert_nil @non_sponsor.sponsors_listing
      assert_nil @non_sponsor.sponsors_country_of_residence
    end
  end

  context "#sponsoring_parent_organization and #async_sponsoring_parent_organization" do
    test "returns nil when there's no org profile with a sponsoring org" do
      assert_nil @org.sponsoring_parent_organization_profile,
        "need an org with no sponsoring parent org profile"
      assert_nil @org.sponsoring_parent_organization
      assert_nil @org.async_sponsoring_parent_organization.sync
    end

    test "returns linked org when a sponsoring parent org profile exists" do
      linked_org = create(:organization)
      create(:organization_profile, organization: linked_org, sponsoring_linked_organization: @org)
      assert_equal linked_org, @org.sponsoring_parent_organization
      assert_equal linked_org, @org.async_sponsoring_parent_organization.sync
    end

    test "is not bidirectional" do
      linked_org = create(:organization)
      create(:organization_profile, organization: linked_org, sponsoring_linked_organization: @org)
      assert_nil linked_org.sponsoring_parent_organization
      assert_nil linked_org.async_sponsoring_parent_organization.sync
    end
  end

  context "#private_sponsor_identity_visible_to?" do
    test "true for org for org admin viewer" do
      org = create(:organization)
      org_admin = org.admins.first

      assert org.private_sponsor_identity_visible_to?(org_admin)
    end

    test "true for org for billing manager viewer" do
      org = create(:organization)
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      assert org.private_sponsor_identity_visible_to?(billing_manager)
    end

    test "true for org for admin viewer of linked org" do
      org_that_gets_credit_admin = @org_that_gets_credit.admins.first
      assert @org_that_pays.private_sponsor_identity_visible_to?(org_that_gets_credit_admin)
    end

    test "true for org for billing manager viewer of linked org" do
      assert @org_that_pays.private_sponsor_identity_visible_to?(@org_that_gets_credit_billing_manager)
    end

    test "true for sponsorship from org for org member viewer" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)

      assert org.private_sponsor_identity_visible_to?(org_member)
    end

    test "true for org for viewer who is a member of linked org" do
      org_that_gets_credit_member = create(:user)
      @org_that_gets_credit.add_member(org_that_gets_credit_member)

      assert @org_that_gets_credit.private_sponsor_identity_visible_to?(org_that_gets_credit_member)
      assert @org_that_pays.private_sponsor_identity_visible_to?(org_that_gets_credit_member)
    end

    test "false for org for viewer who is not member of linked org or parent org" do
      org_that_gets_credit_member = create(:user)
      @org_that_gets_credit.add_member(org_that_gets_credit_member)
      rando = create(:user)

      refute @org_that_pays.private_sponsor_identity_visible_to?(rando)
      refute @org_that_gets_credit.private_sponsor_identity_visible_to?(rando)
    end

    test "false for org for non-org-member viewer" do
      rando = create(:user)
      org = create(:organization)

      refute org.private_sponsor_identity_visible_to?(rando)
    end

    test "false for user for anonymous viewer" do
      sponsor = create(:user)

      refute sponsor.private_sponsor_identity_visible_to?(nil)
    end

    test "true for user for themselves" do
      sponsor = create(:user)

      assert sponsor.private_sponsor_identity_visible_to?(sponsor)
    end

    test "false for user for a different user" do
      sponsor = create(:user)
      rando = create(:user)

      refute sponsor.private_sponsor_identity_visible_to?(rando)
    end
  end

  context "#sponsorship_amounts_as_sponsor_readable_by? and #async_sponsorship_amounts_as_sponsor_readable_by?" do
    test "true for sponsorship from org for org admin viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      org_admin = org.admins.first

      assert org.sponsorship_amounts_as_sponsor_readable_by?(org_admin)
      assert org.async_sponsorship_amounts_as_sponsor_readable_by?(org_admin).sync
    end

    test "true for sponsorship from org for billing manager viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      billing_manager = create(:user)
      org.billing.add_manager(billing_manager, actor: org.admins.first)

      assert org.sponsorship_amounts_as_sponsor_readable_by?(billing_manager)
      assert org.async_sponsorship_amounts_as_sponsor_readable_by?(billing_manager).sync
    end

    test "true for sponsorship from org for admin viewer of linked org" do
      org_that_gets_credit_admin = @org_that_gets_credit.admins.first

      sponsorship = create(:sponsorship, sponsor: @org_that_pays)
      assert @org_that_pays.sponsorship_amounts_as_sponsor_readable_by?(org_that_gets_credit_admin)
      assert @org_that_pays.async_sponsorship_amounts_as_sponsor_readable_by?(org_that_gets_credit_admin).sync
    end

    test "true for sponsorship from org for billing manager viewer of linked org" do
      sponsorship = create(:sponsorship, sponsor: @org_that_pays)
      assert @org_that_pays.sponsorship_amounts_as_sponsor_readable_by?(@org_that_gets_credit_billing_manager)
      assert @org_that_pays.async_sponsorship_amounts_as_sponsor_readable_by?(
        @org_that_gets_credit_billing_manager,
      ).sync
    end

    test "false for sponsorship from org for org member viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      refute org.sponsorship_amounts_as_sponsor_readable_by?(org_member)
      refute org.async_sponsorship_amounts_as_sponsor_readable_by?(org_member).sync
    end

    test "false for sponsorship from org for viewer who is a member of linked org" do
      org_that_gets_credit_member = create(:user)
      @org_that_gets_credit.add_member(org_that_gets_credit_member)

      sponsorship = create(:sponsorship, sponsor: @org_that_pays)
      refute @org_that_pays.sponsorship_amounts_as_sponsor_readable_by?(org_that_gets_credit_member)
      refute @org_that_pays.async_sponsorship_amounts_as_sponsor_readable_by?(org_that_gets_credit_member).sync
    end

    test "false for sponsorship from org for non-org member viewer" do
      sponsorship = create(:sponsorship, :from_org)
      rando = create(:user)
      sponsor = sponsorship.sponsor

      refute sponsor.sponsorship_amounts_as_sponsor_readable_by?(rando)
      refute sponsor.async_sponsorship_amounts_as_sponsor_readable_by?(rando).sync
    end

    test "false for sponsorship to user for anonymous viewer" do
      sponsorship = create(:sponsorship)
      sponsor = sponsorship.sponsor

      refute sponsor.sponsorship_amounts_as_sponsor_readable_by?(nil)
      refute sponsor.async_sponsorship_amounts_as_sponsor_readable_by?(nil).sync
    end

    test "true for sponsorship for its sponsor" do
      sponsorship = create(:sponsorship)
      sponsor = sponsorship.sponsor

      assert sponsor.sponsorship_amounts_as_sponsor_readable_by?(sponsor)
      assert sponsor.async_sponsorship_amounts_as_sponsor_readable_by?(sponsor).sync
    end

    test "false for sponsorship to user for a viewer who is not involved" do
      sponsorship = create(:sponsorship)
      sponsor = sponsorship.sponsor
      rando = create(:user)

      refute sponsor.sponsorship_amounts_as_sponsor_readable_by?(rando)
      refute sponsor.async_sponsorship_amounts_as_sponsor_readable_by?(rando).sync
    end

    test "memoizes result by viewer" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      allowed_viewer1 = org.admins.first
      allowed_viewer2 = create(:user)
      org.billing.add_manager(allowed_viewer2, actor: org.admins.first)
      disallowed_viewer1 = create(:user)
      disallowed_viewer2 = create(:user)
      org.add_member(disallowed_viewer2)

      assert_query_count(1, ignore_feature_flags: true) do
        assert org.sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer1)
        assert org.async_sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer1).sync
      end
      assert_query_count(2, ignore_feature_flags: true) do
        assert org.sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer2)
        assert org.async_sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer2).sync
      end
      assert_query_count(3, ignore_feature_flags: true) do
        refute org.sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer1)
        refute org.async_sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer1).sync
      end
      assert_query_count(2, ignore_feature_flags: true) do
        refute org.sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer2)
        refute org.async_sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer2).sync
      end

      assert_query_count(0, ignore_feature_flags: true) do
        assert org.sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer1)
        assert org.async_sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer1).sync
        assert org.sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer2)
        assert org.async_sponsorship_amounts_as_sponsor_readable_by?(allowed_viewer2).sync
        refute org.sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer1)
        refute org.async_sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer1).sync
        refute org.sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer2)
        refute org.async_sponsorship_amounts_as_sponsor_readable_by?(disallowed_viewer2).sync
      end
    end
  end

  context "#actively_sponsoring?" do
    test "true when user is sponsoring someone" do
      assert_predicate @sponsor, :actively_sponsoring?
    end

    test "true when org is sponsoring someone" do
      assert_predicate @org_sponsor, :actively_sponsoring?
    end

    test "false when user is not sponsoring anyone" do
      refute_predicate @sponsorable, :actively_sponsoring?
    end

    test "false when org is not sponsoring anyone" do
      refute_predicate @org, :actively_sponsoring?
    end

    test "true when user has made a recent one-time payment" do
      sponsorship = create(:sponsorship, tier: @one_time_tier)
      assert_predicate sponsorship.sponsor, :actively_sponsoring?
    end

    test "false when user made a one-time payment long ago" do
      sponsorship = create(:sponsorship, :expired, tier: @one_time_tier)
      refute_predicate sponsorship.sponsor, :actively_sponsoring?
    end
  end

  context "#sponsorship_amounts_as_sponsorable_readable_by? and #async_sponsorship_amounts_as_sponsorable_readable_by?" do
    test "true for org for org admin viewer" do
      org_admin = @org.admins.first
      assert @org.sponsorship_amounts_as_sponsorable_readable_by?(org_admin)
      assert @org.async_sponsorship_amounts_as_sponsorable_readable_by?(org_admin).sync
    end

    test "false for org for org billing manager viewer" do
      billing_manager = create(:user)
      @org.billing.add_manager(billing_manager, actor: @org.admins.first)

      refute @org.sponsorship_amounts_as_sponsorable_readable_by?(billing_manager)
      refute @org.async_sponsorship_amounts_as_sponsorable_readable_by?(billing_manager).sync
    end

    test "false for org for org member viewer" do
      org_member = create(:user)
      @org.add_member(org_member)

      refute @org.sponsorship_amounts_as_sponsorable_readable_by?(org_member)
      refute @org.async_sponsorship_amounts_as_sponsorable_readable_by?(org_member).sync
    end

    test "false for org for non-org member viewer" do
      rando = create(:user)
      refute @org.sponsorship_amounts_as_sponsorable_readable_by?(rando)
      refute @org.async_sponsorship_amounts_as_sponsorable_readable_by?(rando).sync
    end

    test "false for org for anonymous viewer" do
      refute @org.sponsorship_amounts_as_sponsorable_readable_by?(nil)
      refute @org.async_sponsorship_amounts_as_sponsorable_readable_by?(nil).sync
    end

    test "false for user for anonymous viewer" do
      refute @sponsorable.sponsorship_amounts_as_sponsorable_readable_by?(nil)
      refute @sponsorable.async_sponsorship_amounts_as_sponsorable_readable_by?(nil).sync
    end

    test "true for the sponsored maintainer" do
      assert @sponsorable.sponsorship_amounts_as_sponsorable_readable_by?(@sponsorable)
      assert @sponsorable.async_sponsorship_amounts_as_sponsorable_readable_by?(@sponsorable).sync
    end

    test "false for user for a viewer who is not involved" do
      rando = create(:user)
      refute @sponsorable.sponsorship_amounts_as_sponsorable_readable_by?(rando)
      refute @sponsorable.async_sponsorship_amounts_as_sponsorable_readable_by?(rando).sync
    end
  end

  context "#actively_being_sponsored?" do
    test "true when user is being sponsored" do
      assert_predicate @sponsorable, :actively_being_sponsored?
    end

    test "true when org is being sponsored" do
      create(:sponsorship, sponsorable: @org)
      assert_predicate @org, :actively_being_sponsored?
    end

    test "false when user is not being sponsored" do
      refute_predicate @sponsor, :actively_being_sponsored?
    end

    test "false when org is not being sponsored" do
      refute_predicate @org_sponsor, :actively_being_sponsored?
    end

    test "true when user recently received a one-time payment" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorship = create(:sponsorship, tier: one_time_tier)
      assert_predicate sponsorship.sponsorable, :actively_being_sponsored?
    end

    test "false when user received a one-time payment long ago" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorship = create(:sponsorship, :expired, tier: one_time_tier)
      refute_predicate sponsorship.sponsorable, :actively_being_sponsored?
    end
  end

  context ".sponsorable_user_ids_from" do
    test "includes sponsorable org" do
      assert_equal Set.new([@org.id]), User.sponsorable_user_ids_from([@org.id])
    end

    test "includes sponsorable user" do
      assert_instance_of User, @sponsorable, "need a sponsorable User for this test"
      assert_equal Set.new([@sponsorable.id]), User.sponsorable_user_ids_from([@sponsorable.id])
    end

    test "omits sponsorable viewer by default" do
      assert_instance_of User, @sponsorable, "need a sponsorable User for this test"
      assert_empty User.sponsorable_user_ids_from([@sponsorable.id], viewer: @sponsorable)
    end

    test "includes sponsorable viewer when specified" do
      assert_instance_of User, @sponsorable, "need a sponsorable User for this test"
      assert_equal Set.new([@sponsorable.id]),
        User.sponsorable_user_ids_from([@sponsorable.id], viewer: @sponsorable, include_viewer: true)
    end

    if GitHub.spamminess_check_enabled?
      test "omits spammy sponsorable for anonymous viewer" do
        assert_empty User.sponsorable_user_ids_from([@spammy_sponsorable.id], viewer: nil)
      end

      test "omits spammy sponsorable for regular viewer" do
        assert_empty User.sponsorable_user_ids_from([@spammy_sponsorable.id], viewer: @non_sponsor)
      end

      test "omits spammy sponsorable for staff viewer" do
        assert_empty User.sponsorable_user_ids_from([@spammy_sponsorable.id], viewer: @staff)
      end

      test "includes spammy sponsorable when they're the viewer" do
        result = User.sponsorable_user_ids_from([@spammy_sponsorable.id], viewer: @spammy_sponsorable,
          include_viewer: true)
        assert_equal Set.new([@spammy_sponsorable.id]), result
      end
    end

    test "does not include non-sponsorable user" do
      assert_empty User.sponsorable_user_ids_from([@non_sponsor.id])
    end

    # https://github.com/github/sponsors/issues/2227
    test "does not include sponsorable who is blocking the viewer" do
      viewer = @sponsor
      assert @sponsorable.block(viewer)
      assert_empty User.sponsorable_user_ids_from([@sponsorable.id], viewer: viewer)
    end

    test "does not include user who does not have a listing" do
      user = create(:user, :verified)
      assert_empty User.sponsorable_user_ids_from([user.id])
    end

    test "does not include user without an approved listing" do
      user = create(:user, :verified)
      create(:sponsors_listing, :pending_approval, sponsorable: user)
      assert_empty User.sponsorable_user_ids_from([user.id])
    end
  end

  context ".sponsorable_users_from_logins" do
    test "includes sponsorable users and omits non-sponsorable users" do
      sponsorables = @sponsorships_for_sponsor.map(&:sponsorable)
      sponsorable_logins = sponsorables.map(&:login)
      non_sponsorable_logins = [@non_sponsor.login]

      result = User.sponsorable_users_from_logins(sponsorable_logins + non_sponsorable_logins)

      assert_same_elements sponsorables, result
    end

    test "includes sponsorable org" do
      assert_equal [@org], User.sponsorable_users_from_logins([@org.login])
    end

    test "omits user who has a Sponsors listing that's not public" do
      draft_listing = create(:sponsors_listing, :draft)
      assert_empty User.sponsorable_users_from_logins([draft_listing.sponsorable_login])
    end
  end

  context "sponsorships_as_sponsorable relation" do
    test "ranks sponsorships by sponsor rank" do
      sponsor2 = @sponsorship2.sponsor
      sponsor3 = @sponsorship3.sponsor

      @non_sponsor.follow(sponsor2)

      sorted_sponsorships = @sponsorable.sponsorships_as_sponsorable.ranked(for_user: @non_sponsor)

      assert_equal 3, sorted_sponsorships.count
      assert_equal [@sponsorship2, @sponsorship1, @sponsorship3], sorted_sponsorships
    end
  end

  context "sponsorships_as_sponsor relation" do
    test "destroys sponsorship when user is destroyed" do
      @sponsorship1.sponsor.destroy!
      assert_nil Sponsorship.find_by(id: @sponsorship1.id)
    end

    test "ranks sponsorships by sponsorable rank" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor

      sponsorable1 = sponsorship1.sponsorable
      sponsorable2 = sponsorship2.sponsorable
      sponsorable3 = sponsorship3.sponsorable

      @non_sponsor.follow(sponsorable2)

      sorted_sponsorships = @sponsor.sponsorships_as_sponsor.ranked(for_user: @non_sponsor)

      assert_equal 3, sorted_sponsorships.count
      assert_equal [sponsorship2, sponsorship1, sponsorship3], sorted_sponsorships
    end

    test "includes inactive sponsorship" do
      sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable)
      sponsor = sponsorship.sponsor
      assert_equal [sponsorship], sponsor.sponsorships_as_sponsor
    end

    test "includes sponsorship from linked org when called on an org sponsor" do
      sponsorship = create(:sponsorship, sponsor: @org_that_pays, sponsorable: @sponsorable)
      assert_equal [sponsorship], @org_that_pays.sponsorships_as_sponsor
    end
  end

  context "#potential_sponsor_ids" do
    test "includes just the user's own ID when user does not own any orgs or act as billing manager" do
      assert_equal [@sponsor.id], @sponsor.potential_sponsor_ids
    end

    test "does not include the ID of an org the user just belongs to" do
      @org_sponsor.add_member(@sponsor)
      refute_includes @sponsor.potential_sponsor_ids, @org_sponsor.id
    end

    test "includes the IDs of orgs the user is admin of" do
      other_org = create(:organization)
      other_org.add_admin(@org_sponsor_admin)

      result = @org_sponsor_admin.potential_sponsor_ids

      assert_includes result, @org_sponsor.id
      assert_includes result, other_org.id
    end

    test "does not include ID of a different user" do
      refute_includes @sponsor.potential_sponsor_ids, @org_sponsor_admin.id
    end

    test "includes the IDs of orgs the user is billing manager of" do
      assert_includes @billing_manager.potential_sponsor_ids, @org_sponsor.id
    end
  end

  context "#potential_linked_organization_sponsor_ids" do
    test "does not include the user's own ID" do
      refute_includes @sponsor.potential_linked_organization_sponsor_ids, @sponsor.id
    end

    test "does not include the ID of an org the user just belongs to" do
      @org_sponsor.add_member(@sponsor)
      refute_includes @sponsor.potential_linked_organization_sponsor_ids, @org_sponsor.id
    end

    test "does not include ID of a different user" do
      refute_includes @sponsor.potential_linked_organization_sponsor_ids, @org_sponsor_admin.id
    end

    test "does not include IDs of orgs the user is directly admin of" do
      other_org = create(:organization)
      other_org.add_admin(@org_sponsor_admin)

      result = @org_sponsor_admin.potential_linked_organization_sponsor_ids

      refute_includes result, @org_sponsor.id
      refute_includes result, other_org.id
    end

    test "does not include IDs of orgs the user is directly billing manager of" do
      other_org = create(:organization)
      other_org.billing.add_manager(@billing_manager, actor: other_org.admin)

      result = @billing_manager.potential_linked_organization_sponsor_ids

      refute_includes result, @org_sponsor.id
      refute_includes result, other_org.id
    end

    test "includes the ID of org that is linked to an org the user admins" do
      assert_includes @org_that_gets_credit.admin.potential_linked_organization_sponsor_ids, @org_that_pays.id
      refute_includes @org_that_pays.admin.potential_linked_organization_sponsor_ids, @org_that_gets_credit.id,
        "relationship should not be bidirectional"
    end

    test "includes the ID of org that is linked to an org the user is billing manager of" do
      assert_includes @org_that_gets_credit_billing_manager.potential_linked_organization_sponsor_ids,
        @org_that_pays.id

      org_that_pays_billing_manager = create(:user)
      @org_that_pays.billing.add_manager(org_that_pays_billing_manager, actor: @org_that_pays.admin)
      refute_includes org_that_pays_billing_manager.potential_linked_organization_sponsor_ids,
        @org_that_gets_credit.id, "relationship should not be bidirectional"
    end
  end

  context "#can_be_enrolled_in_sponsors_by?" do
    test "false for user without a verified email" do
      user = create(:user)
      refute user.can_be_enrolled_in_sponsors_by?(user)
    end if GitHub.email_verification_enabled?

    test "false for anonymous user" do
      refute @non_sponsor.can_be_enrolled_in_sponsors_by?(nil)
    end

    test "false for org when actor is not an org admin" do
      org = create(:organization)
      rando = create(:user)
      refute org.can_be_enrolled_in_sponsors_by?(rando)
    end

    test "true for org when actor is an admin" do
      admin = create(:user)
      org = create(:organization, admin: admin)
      assert org.can_be_enrolled_in_sponsors_by?(admin)
    end

    test "true for user with a verified email" do
      assert @non_sponsor.can_be_enrolled_in_sponsors_by?(@non_sponsor)
    end

    test "false for spammy user" do
      spammer = create(:spammy_user)
      refute spammer.can_be_enrolled_in_sponsors_by?(spammer)
    end if GitHub.spamminess_check_enabled?

    test "false for banned listing" do
      create(:sponsors_listing, :banned, sponsorable: @non_sponsor)
      refute @non_sponsor.can_be_enrolled_in_sponsors_by?(@non_sponsor)
    end
  end

  context "#sponsors_listing_email" do
    test "returns Sponsors listing contact email address" do
      listing = @sponsorable.sponsors_listing
      assert_equal listing.contact_email_address, @sponsorable.sponsors_listing_email
    end

    test "returns nil when user is not part of Sponsors" do
      assert_nil @non_sponsor.sponsors_listing_email
    end

    test "billing_email for orgs" do
      assert_equal @org.billing_email, @org.sponsors_listing_email
    end
  end

  context "#sponsors_payouts_enabled?" do
    test "true when Stripe payouts are enabled" do
      create(:stripe_connect_account, payouts_enabled: true, sponsors_listing: @sponsors_listing)
      assert_predicate @sponsorable, :sponsors_payouts_enabled?
    end

    test "false when Stripe payouts are not enabled" do
      create(:stripe_connect_account, :payouts_disabled, sponsors_listing: @sponsors_listing)
      refute_predicate @sponsorable, :sponsors_payouts_enabled?
    end

    test "false when sponsorable does not have a Stripe account" do
      assert_nil @sponsors_listing.active_stripe_connect_account
      refute_predicate @sponsorable, :sponsors_payouts_enabled?
    end
  end

  context "active_recurring_sponsorships_as_sponsorable scope" do
    test "includes active recurring sponsorship where user is the maintainer" do
      assert_predicate @sponsorship1, :recurring_payment?
      assert_predicate @sponsorship1, :active?
      sponsorable = @sponsorship1.sponsorable
      assert_includes sponsorable.active_recurring_sponsorships_as_sponsorable,
        @sponsorship1
    end

    test "doesn't include inactive sponsorship" do
      sponsorship = create(:sponsorship, :inactive)
      assert_predicate sponsorship, :recurring_payment?
      sponsorable = sponsorship.sponsorable
      refute_includes sponsorable.active_recurring_sponsorships_as_sponsorable,
        sponsorship
    end

    test "doesn't include one-time sponsorship" do
      sponsorship = create(:sponsorship, tier: @one_time_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)
      refute_includes @sponsorable.active_recurring_sponsorships_as_sponsorable,
        sponsorship
    end

    test "doesn't include active recurring sponsorship where user is the sponsor" do
      assert_predicate @sponsorship1, :recurring_payment?
      assert_predicate @sponsorship1, :active?
      sponsor = @sponsorship1.sponsor
      refute_includes sponsor.active_recurring_sponsorships_as_sponsorable,
        @sponsorship1
    end
  end

  # See also tests for organizations in packages/github_sponsors/test/models/organization/sponsors_dependency_test.rb
  context "#active_sponsorships_as_sponsor_relation" do
    test "includes active sponsorship where the user is the sponsor" do
      sponsorship = @sponsorships_for_sponsor.first
      assert_includes @sponsor.active_sponsorships_as_sponsor_relation, sponsorship
    end

    test "includes active sponsorship where the org is the sponsor" do
      assert_includes @org_sponsor.active_sponsorships_as_sponsor_relation, @sponsorship_with_org_sponsor
    end

    test "includes active one-time sponsorship where the org is the sponsor" do
      assert_includes @org_sponsor.active_sponsorships_as_sponsor_relation,
        @one_time_sponsorship_with_org_sponsor
    end

    test "excludes inactive sponsorship where the user is the sponsor" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, active: false)
      refute_includes @sponsor.active_sponsorships_as_sponsor_relation, sponsorship
    end

    test "excludes inactive sponsorship where the org is the sponsor" do
      sponsorship = create(:sponsorship, sponsor: @org_sponsor, active: false)
      refute_includes @org_sponsor.active_sponsorships_as_sponsor_relation, sponsorship
    end

    test "excludes active sponsorship where the user is the one being sponsored" do
      sponsorship = @sponsorships_for_sponsor.first
      sponsorable = sponsorship.sponsorable
      assert_predicate sponsorable, :user?, "need a user sponsorable for this test"
      refute_includes sponsorable.active_sponsorships_as_sponsor_relation, sponsorship
    end

    test "excludes active sponsorship where the org is the one being sponsored" do
      sponsorship = create(:sponsorship, sponsorable: @org)
      refute_includes @org.active_sponsorships_as_sponsor_relation, sponsorship
    end
  end

  # See also tests for orgs in packages/github_sponsors/test/models/organization/sponsors_dependency_test.rb
  context "#active_sponsorships_as_sponsor" do
    test "can be efficiently loaded for many sponsors at once" do
      inactive_sponsor = create(:sponsorship, :inactive).sponsor
      private_sponsorship = create(:sponsorship, :private)
      private_sponsor = private_sponsorship.sponsor
      sponsors = [@sponsor, @non_sponsor, inactive_sponsor, @sponsorable, private_sponsor]

      expected_queries_by_table = { sponsorships: 1 }

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          GitHub::PrefillAssociations.prefill_batch_method(sponsors, :active_sponsorships_as_sponsor)
        end
      end

      assert_query_count(0) do
        assert_same_elements @sponsorships_for_sponsor, @sponsor.active_sponsorships_as_sponsor
        assert_empty @non_sponsor.active_sponsorships_as_sponsor
        assert_empty inactive_sponsor.active_sponsorships_as_sponsor
        assert_empty @sponsorable.active_sponsorships_as_sponsor
        assert_equal [private_sponsorship], private_sponsor.active_sponsorships_as_sponsor
      end
    end

    test "respects given scope for filtering results" do
      inactive_sponsor = create(:sponsorship, :inactive).sponsor
      private_sponsor = create(:sponsorship, :private).sponsor
      sponsors = [@sponsor, @non_sponsor, inactive_sponsor, @sponsorable, private_sponsor]
      scope = Sponsorship.privacy_public

      expected_queries_by_table = { sponsorships: 1 }

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          GitHub::PrefillAssociations.prefill_batch_method(sponsors, :active_sponsorships_as_sponsor,
            { scope: scope })
        end
      end

      assert_query_count(0) do
        assert_same_elements @sponsorships_for_sponsor, @sponsor.active_sponsorships_as_sponsor(scope: scope)
        assert_empty @non_sponsor.active_sponsorships_as_sponsor(scope: scope)
        assert_empty inactive_sponsor.active_sponsorships_as_sponsor(scope: scope)
        assert_empty @sponsorable.active_sponsorships_as_sponsor(scope: scope)
        assert_empty private_sponsor.active_sponsorships_as_sponsor(scope: scope),
          "should not have returned private sponsorships because of the given scope"
      end
    end
  end

  context "#sponsorable?" do
    if GitHub.sponsors_enabled?
      test "returns true for user with an approved Sponsors listing" do
        assert_predicate @sponsorable, :sponsorable?
      end

      test "returns true for an org with an approved Sponsors listing" do
        assert_predicate @org, :sponsorable?
      end

      test "returns false for user without an approved Sponsors listing" do
        user_with_accepted_membership = create(:user, :sponsors_program_member)
        refute_predicate user_with_accepted_membership, :sponsorable?
      end

      test "returns false for org without an approved Sponsors listing" do
        org_with_accepted_membership = create(:organization, :sponsors_program_member)
        refute_predicate org_with_accepted_membership, :sponsorable?
      end
    else
      test "returns false" do
        refute_predicate @sponsorable, :sponsorable?
        refute_predicate @org, :sponsorable?
      end
    end
  end

  context "#newest_sponsors_business_tax_identifier" do
    test "returns the newest SponsorBusinessTaxIdentifier associated with this user" do
      create(:sponsors_business_tax_identifier, user: @sponsorable, created_at: 1.minute.ago)
      newest = create(:sponsors_business_tax_identifier, user: @sponsorable)

      assert_equal @sponsorable.newest_sponsors_business_tax_identifier, newest
    end
  end

  context ".active_sponsorships_as_sponsorable" do
    test "includes active sponsorship where the user is being sponsored" do
      assert_includes @sponsorable.active_sponsorships_as_sponsorable, @sponsorship1
    end

    test "includes active sponsorship where the org is being sponsored" do
      sponsorship = create(:sponsorship, sponsorable: @org)
      assert_includes @org.active_sponsorships_as_sponsorable, sponsorship
    end

    test "excludes inactive sponsorship where the user is being sponsored" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable, active: false)
      refute_includes @sponsorable.active_sponsorships_as_sponsorable, sponsorship
    end

    test "excludes inactive sponsorship where the org is being sponsored" do
      sponsorship = create(:sponsorship, sponsorable: @org, active: false)
      refute_includes @org.active_sponsorships_as_sponsorable, sponsorship
    end

    test "excludes active sponsorship where the user is the sponsor" do
      sponsorship = @sponsorships_for_sponsor.first
      refute_includes @sponsor.active_sponsorships_as_sponsorable, sponsorship
    end

    test "excludes active sponsorship where the org is the sponsor" do
      refute_includes @org_sponsor.active_sponsorships_as_sponsorable, @sponsorship_with_org_sponsor
    end
  end

  context "#sponsors_waitlisted?" do
    test "true when user has a listing that's waitlisted" do
      listing = create(:sponsors_listing, :waitlisted)
      assert_predicate listing.sponsorable, :sponsors_waitlisted?
    end

    test "false when user has a listing that's not waitlisted" do
      refute_predicate @sponsorable, :sponsors_waitlisted?
    end

    test "false when user has no listing" do
      assert_nil @non_sponsor.sponsors_listing
      refute_predicate @non_sponsor, :sponsors_waitlisted?
    end
  end

  context "#sponsors_program_member?" do
    test "returns false if the user's Sponsors listing is waitlisted" do
      listing = create(:sponsors_listing, :waitlisted)
      assert_predicate listing, :waitlisted?
      refute_predicate listing.sponsorable, :sponsors_program_member?
    end

    test "returns true if the user's Sponsors listing is a draft" do
      listing = create(:sponsors_listing, :draft)
      assert_predicate listing.sponsorable, :sponsors_program_member?
    end

    test "returns false if the user does not have a sponsors listing" do
      assert_nil @non_sponsor.sponsors_listing
      refute_predicate @non_sponsor, :sponsors_program_member?
    end

    test "returns true if the org's Sponsors listing is draft" do
      listing = create(:sponsors_listing, :for_org)
      assert_predicate listing.sponsorable, :sponsors_program_member?
    end

    test "returns false if the organization does not have a sponsors listing" do
      org = build(:organization)
      assert_nil org.sponsors_listing
      refute_predicate org, :sponsors_program_member?
    end

    test "returns true if sponsorable has a listing pending approval" do
      listing = create(:sponsors_listing, :pending_approval)
      assert_predicate listing.sponsorable, :sponsors_program_member?
    end

    test "returns true if sponsorable has an approved listing" do
      listing = create(:sponsors_listing, :approved)
      assert_predicate listing.sponsorable, :sponsors_program_member?
    end

    test "returns false if sponsorable has a banned listing" do
      listing = create(:sponsors_listing, :banned)
      refute_predicate listing.sponsorable, :sponsors_program_member?
    end

    test "returns true if sponsorable has a disabled listing" do
      listing = create(:sponsors_listing, :disabled)
      assert_predicate listing.sponsorable, :sponsors_program_member?
    end
  end

  context "#sponsorable_by?" do
    unless GitHub.sponsors_enabled?
      test "returns false when Sponsors is disabled" do
        refute @sponsorable.sponsorable_by?(@sponsor)
      end
    end

    test "returns false if viewing yourself" do
      assert_predicate @sponsorable, :sponsors_program_member?
      refute @sponsorable.sponsorable_by?(@sponsorable)
    end

    test "returns false if user has no listing" do
      assert_nil @non_sponsor.sponsors_listing
      refute @non_sponsor.sponsorable_by?(@sponsor)
    end

    test "returns false if sponsorable's listing is not approved" do
      sponsors_listing = @sponsorable.sponsors_listing
      sponsors_listing.update_columns(
        state: SponsorsListing.state_value(:draft)
      )
      assert_predicate @sponsorable.reload, :sponsors_program_member?

      refute @sponsorable.sponsorable_by?(@sponsor)
    end

    test "returns false if sponsorable's membership is not accepted" do
      listing = @sponsorable.sponsors_listing
      listing.actor = @staff
      listing.ban!(banned_reason: "o noes")
      refute_predicate @sponsorable.reload, :sponsors_program_member?

      refute @sponsorable.sponsorable_by?(@sponsor)
    end

    test "returns true for program members with an approved listing" do
      assert_predicate @sponsorable, :sponsors_program_member?
      assert_predicate @sponsorable.sponsors_listing, :approved?
      assert @sponsorable.sponsorable_by?(@sponsor)
    end

    test "returns true if user is sponsorable for logged out viewer" do
      assert_predicate @sponsorable, :sponsors_program_member?
      assert @sponsorable.sponsorable_by?(nil)
    end

    test "returns false if the user is not sponsorable for logged out viewer" do
      @sponsorable.sponsors_listing.actor = @staff
      @sponsorable.sponsors_listing.ban!(banned_reason: "o noes")
      refute_predicate @sponsorable.reload, :sponsors_program_member?

      refute @sponsorable.sponsorable_by?(nil)
    end

    test "returns false when viewer has a locked one-time sponsorship for the user" do
      create(:sponsorship, tier: @one_time_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)
      refute @sponsorable.sponsorable_by?(@sponsor),
        "expected sponsor not to be able to re-sponsor the maintainer while their OTP is locked"
    end

    test "returns true when viewer has an unlocked sponsorship for the user" do
      create(:sponsorship, :unlocked, tier: @one_time_tier, sponsor: @sponsor,
        sponsorable: @sponsorable)
      assert @sponsorable.sponsorable_by?(@sponsor),
        "expected sponsor to be able to re-sponsor the maintainer now that their OTP is unlocked"
    end

    # https://github.com/github/sponsors/issues/2227
    test "returns false when maintainer has blocked the person trying to sponsor" do
      assert @sponsorable.block(@sponsor)
      refute @sponsorable.sponsorable_by?(@sponsor)
    end
  end

  context "#total_monthly_pledged_in_dollars" do
    test "returns 0 if there are no sponsorships" do
      Sponsorship.where(sponsorable: @sponsorable).delete_all
      assert_equal Billing::Money.zero, @sponsorable.total_monthly_pledged_in_dollars
    end

    test "returns total monthly pledged on active sponsorships for a sponsorable" do
      subscribed_tiers = [@sponsorship1, @sponsorship2, @sponsorship3].map(&:tier)
      expected_dollars = subscribed_tiers.sum(&:monthly_price_in_cents) / 100

      assert_equal expected_dollars, @sponsorable.total_monthly_pledged_in_dollars.to_i
    end

    test "omits one-time sponsorships" do
      one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
      sponsorable = one_time_tier.sponsorable
      create(:sponsorship, sponsorable: sponsorable, tier: one_time_tier)

      assert_equal Billing::Money.zero, sponsorable.total_monthly_pledged_in_dollars
    end

    test "returns 0 when user has no Sponsors listing" do
      assert_equal Billing::Money.zero, @non_sponsor.total_monthly_pledged_in_dollars
    end
  end

  context "#update_sponsors_listing_slug" do
    if GitHub.sponsors_enabled?
      test "returns true when user has no Sponsors listing" do
        assert @non_sponsor.update_sponsors_listing_slug("newLogin")
      end

      test "returns true when it's not safe to change the Sponsors listing slug" do
        @sponsorable.sponsors_listing.stubs(:safe_to_update_slug?).returns(false)
        @sponsorable.sponsors_listing.expects(:update_slug).never

        assert @sponsorable.update_sponsors_listing_slug("newLogin")
      end

      test "returns true when the Sponsors listing slug updates successfully" do
        @sponsorable.sponsors_listing.stubs(:safe_to_update_slug?).returns(true)
        @sponsorable.sponsors_listing.expects(:update_slug).once.with(new_login: "newLogin").returns(true)

        assert @sponsorable.update_sponsors_listing_slug("newLogin")
      end

      test "returns false when the Sponsors listing slug does not update successfully" do
        @sponsorable.sponsors_listing.stubs(:safe_to_update_slug?).returns(true)
        @sponsorable.sponsors_listing.expects(:update_slug).once.with(new_login: "newLogin").returns(false)

        refute @sponsorable.update_sponsors_listing_slug("newLogin")
      end
    else
      test "returns true when Sponsors is disabled" do
        assert @sponsorable.update_sponsors_listing_slug("newLogin")
      end
    end
  end

  context "#total_sponsors" do
    test "returns 0 if there are no sponsorships for the listing" do
      Sponsorship.where(sponsorable: @sponsorable).delete_all
      assert_equal 0, @sponsorable.reload.total_sponsors
    end

    test "counts public and private sponsors" do
      @sponsorship3.update_columns(privacy_level: "private")
      assert_equal 3, @sponsorable.reload.total_sponsors
    end
  end

  context "#all_active_sponsoring" do
    test "omits inactive sponsorable" do
      create(:sponsorship, :inactive, sponsor: @sponsor, sponsorable: @sponsorable)
      refute_includes @sponsor.all_active_sponsoring, @sponsorable
    end

    test "includes active private sponsorable" do
      create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_includes @sponsor.all_active_sponsoring, @sponsorable
    end

    test "includes active public sponsorable" do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_includes @sponsor.all_active_sponsoring, @sponsorable
    end
  end

  context "#all_active_sponsors" do
    test "omits inactive sponsor" do
      create(:sponsorship, :inactive, sponsor: @sponsor, sponsorable: @sponsorable)
      refute_includes @sponsorable.all_active_sponsors, @sponsor
    end

    test "includes active private sponsor" do
      create(:sponsorship, :private, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_includes @sponsorable.all_active_sponsors, @sponsor
    end

    test "includes active public sponsor" do
      create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable)
      assert_includes @sponsorable.all_active_sponsors, @sponsor
    end

    test "includes linked org sponsor" do
      create(:sponsorship, sponsor: @org_that_pays, sponsorable: @sponsorable)

      result = @sponsorable.all_active_sponsors

      assert_includes result, @org_that_gets_credit
      refute_includes result, @org_that_pays
    end
  end

  context "#async_sponsors_visible_to" do
    test "returns empty if there are no sponsorships for the listing" do
      Sponsorship.where(sponsorable: @sponsorable).delete_all
      assert_empty @sponsorable.async_sponsors_visible_to(nil).sync
    end

    test "returns sponsor for linked org" do
      sponsorship = create(:sponsorship, sponsor: @org_that_pays)
      sponsorable = sponsorship.sponsorable

      sponsors = sponsorable.async_sponsors_visible_to(nil).sync

      assert_equal [@org_that_gets_credit], sponsors
    end

    test "returns only public sponsors for the user when viewer cannot see private sponsors" do
      @sponsorship3.update_columns(privacy_level: "private")

      sponsors = @sponsorable.async_sponsors_visible_to(nil).sync

      assert_includes sponsors, @sponsorship1.sponsor
      assert_includes sponsors, @sponsorship2.sponsor
      refute_includes sponsors, @sponsorship3.sponsor
      assert_equal 2, sponsors.count
    end

    test "returns ranked sponsors for the viewer" do
      viewer = create(:user)

      followed_user1 = @sponsorship1.sponsor
      viewer.follow(followed_user1)

      unfollowed_user = @sponsorship2.sponsor

      followed_user2 = @sponsorship3.sponsor
      viewer.follow(followed_user2)

      sponsors = @sponsorable.async_sponsors_visible_to(viewer).sync

      assert_equal [followed_user2, followed_user1, unfollowed_user], sponsors
    end

    test "returns ranked sponsors in specified direction" do
      viewer = create(:user)

      followed_user1 = @sponsorship1.sponsor
      viewer.follow(followed_user1)

      unfollowed_user = @sponsorship2.sponsor

      followed_user2 = @sponsorship3.sponsor
      viewer.follow(followed_user2)

      sponsors = @sponsorable.async_sponsors_visible_to(viewer, direction: :asc).sync

      assert_equal [unfollowed_user, followed_user1, followed_user2], sponsors
    end

    test "returns sponsors sorted by login when specified" do
      viewer = create(:user)

      sponsor_b = @sponsorship1.sponsor
      sponsor_b.update!(login: "BeautifulChocolateFountain")

      sponsor_a = @sponsorship2.sponsor
      sponsor_a.update!(login: "AsyncFluctuatingTree")

      sponsor_c = @sponsorship3.sponsor
      sponsor_c.update!(login: "CardinalFragilePickle")

      sponsors = @sponsorable.async_sponsors_visible_to(nil, order: GitHubSponsors::Types::SponsorOrder::Login,
        direction: :asc).sync

      assert_equal [sponsor_a, sponsor_b, sponsor_c], sponsors
    end

    test "returns sponsors sorted by reverse login when specified" do
      viewer = create(:user)

      sponsor_b = @sponsorship1.sponsor
      sponsor_b.update!(login: "BaldEggYolk")

      sponsor_a = @sponsorship2.sponsor
      sponsor_a.update!(login: "ArtificialTroubledLemon")

      sponsor_c = @sponsorship3.sponsor
      sponsor_c.update!(login: "CraftySoupedUpCaterpillar")

      sponsors = @sponsorable.async_sponsors_visible_to(nil, order: GitHubSponsors::Types::SponsorOrder::Login,
        direction: :desc).sync

      assert_equal [sponsor_c, sponsor_b, sponsor_a], sponsors
    end

    test "returns all sponsors for the user when viewer can see private sponsors" do
      @sponsorship3.update_columns(privacy_level: "private")

      sponsors = @sponsorable.async_sponsors_visible_to(@sponsorable).sync

      assert_same_elements [@sponsorship1, @sponsorship2, @sponsorship3].map(&:sponsor_id), sponsors.map(&:id)
    end

    test "returns sponsors filtered by single Sponsors tier when provided" do
      tier1, tier2 = @sponsors_listing.sponsors_tiers.first(2)
      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier1.id, privacy_level: "private")
      @sponsorship3.update_columns(subscribable_id: tier2.id)

      sponsors = @sponsorable.async_sponsors_visible_to(@sponsorable, tiers: tier1).sync

      assert_includes sponsors, @sponsorship1.sponsor
      assert_includes sponsors, @sponsorship2.sponsor
      refute_includes sponsors, @sponsorship3.sponsor
    end

    test "returns sponsors filtered by multiple Sponsors tiers when viewed by maintainer" do
      tier1, tier2, tier3 = @sponsors_listing.sponsors_tiers
      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier2.id, privacy_level: "private")
      @sponsorship3.update_columns(subscribable_id: tier3.id)

      sponsors = @sponsorable.async_sponsors_visible_to(@sponsorable, tiers: [tier2, tier3]).sync

      refute_includes sponsors, @sponsorship1.sponsor
      assert_includes sponsors, @sponsorship2.sponsor
      assert_includes sponsors, @sponsorship3.sponsor
    end

    test "returns nothing when viewed anonymously and filtered by tier" do
      tier1, tier2 = @sponsors_listing.sponsors_tiers.first(2)
      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier1.id, privacy_level: "private")
      @sponsorship3.update_columns(subscribable_id: tier2.id)

      assert_empty @sponsorable.async_sponsors_visible_to(nil, tiers: tier1).sync,
        "should not return any sponsors since viewer should not see how much $ each is sponsoring at"
    end

    test "returns only viewer when a sponsor tries to filter by tier" do
      tier1 = @sponsors_listing.default_tier
      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier1.id, privacy_level: "private")
      @sponsorship3.update_columns(subscribable_id: tier1.id)

      sponsors = @sponsorable.async_sponsors_visible_to(@sponsorship1.sponsor, tiers: [tier1]).sync

      assert_includes sponsors, @sponsorship1.sponsor, "should return viewer as sponsor at that tier"
      refute_includes sponsors, @sponsorship2.sponsor, "should not return private sponsor at that tier"
      refute_includes sponsors, @sponsorship3.sponsor,
        "should not return other sponsor at that tier, even when sponsorship is public, because viewer " \
        "shouldn't know $ amount for someone else's sponsorship"
      assert_equal 1, sponsors.size
    end

    test "does not let org members see their org as a sponsor for a particular tier" do
      sponsorable = @sponsorship_with_org_sponsor.sponsorable
      tier = @sponsorship_with_org_sponsor.tier
      someone_elses_sponsorship = create(:sponsorship, sponsorable: sponsorable, tier: tier)

      assert_empty sponsorable.async_sponsors_visible_to(@private_org_member, tiers: tier).sync,
        "should not expose what tier an org is sponsoring at to its members since they can't see prices on the " \
        "org Sponsoring page"
      assert_empty sponsorable.async_sponsors_visible_to(@public_org_member, tiers: tier).sync
    end

    test "lets org members themselves but not their org as sponsors using a particular tier" do
      sponsorable = @sponsorship_with_org_sponsor.sponsorable
      tier = @sponsorship_with_org_sponsor.tier
      someone_elses_sponsorship = create(:sponsorship, sponsorable: sponsorable, tier: tier)
      create(:sponsorship, sponsorable: sponsorable, tier: tier, sponsor: @public_org_member)

      result = sponsorable.async_sponsors_visible_to(@public_org_member, tiers: tier).sync

      refute_includes result, @org_sponsor,
        "should not expose what tier an org is sponsoring at to its members since they can't see prices on the " \
        "org Sponsoring page"
      refute_includes result, someone_elses_sponsorship.sponsor,
        "should not include other sponsor that isn't the viewer or the viewer's org"
      assert_includes result, @public_org_member, "should include viewer"
      assert_equal 1, result.size
    end

    test "lets org admin see their org as a sponsor for a particular tier" do
      sponsorable = @sponsorship_with_org_sponsor.sponsorable
      tier = @sponsorship_with_org_sponsor.tier
      someone_elses_sponsorship = create(:sponsorship, sponsorable: sponsorable, tier: tier)

      assert_equal [@org_sponsor], sponsorable.async_sponsors_visible_to(@org_sponsor_admin, tiers: tier).sync
    end

    test "lets billing manager see their org as a sponsor for a particular tier" do
      sponsorable = @sponsorship_with_org_sponsor.sponsorable
      tier = @sponsorship_with_org_sponsor.tier
      someone_elses_sponsorship = create(:sponsorship, sponsorable: sponsorable, tier: tier)

      assert_equal [@org_sponsor], sponsorable.async_sponsors_visible_to(@billing_manager, tiers: tier).sync
    end

    test "omits spammy sponsor based on who the viewer is" do
      sponsorship = create(:sponsorship, :with_spammy_sponsor)
      spammy_sponsor = sponsorship.sponsor
      sponsorable = sponsorship.sponsorable

      assert_empty sponsorable.async_sponsors_visible_to(sponsorable).sync,
        "should not return spammy sponsor for sponsorable viewer"
      assert_empty sponsorable.async_sponsors_visible_to(nil).sync,
        "should not return spammy sponsor for anonymous viewer"
      assert_equal [spammy_sponsor], sponsorable.async_sponsors_visible_to(spammy_sponsor).sync,
        "should return spammy sponsor when they are the viewer"
    end
  end

  context "#sponsors_visible_to" do
    test "returns empty if there are no sponsorships for the listing" do
      Sponsorship.where(sponsorable: @sponsorable).delete_all
      assert_empty @sponsorable.reload.sponsors_visible_to(nil)
    end

    test "returns sponsor for linked org" do
      sponsorship = create(:sponsorship, sponsor: @org_that_pays)
      sponsorable = sponsorship.sponsorable

      sponsors = sponsorable.sponsors_visible_to(nil)

      assert_equal [@org_that_gets_credit], sponsors
    end

    test "returns only public sponsors for the user when viewer cannot see private sponsors" do
      @sponsorship3.update_columns(privacy_level: "private")

      sponsors = @sponsorable.reload.sponsors_visible_to(nil, sponsorships_scope: Sponsorship.privacy_public)

      assert_includes sponsors, @sponsorship1.sponsor
      assert_includes sponsors, @sponsorship2.sponsor
      refute_includes sponsors, @sponsorship3.sponsor
      assert_equal 2, sponsors.count
    end

    test "returns ranked sponsors for the viewer" do
      viewer = create(:user)

      followed_user1 = @sponsorship1.sponsor
      viewer.follow(followed_user1)

      unfollowed_user = @sponsorship2.sponsor

      followed_user2 = @sponsorship3.sponsor
      viewer.follow(followed_user2)

      sponsors = @sponsorable.sponsors_visible_to(viewer)

      assert_equal [followed_user2, followed_user1, unfollowed_user], sponsors
    end

    test "returns ranked sponsors in specified direction" do
      viewer = create(:user)

      followed_user1 = @sponsorship1.sponsor
      viewer.follow(followed_user1)

      unfollowed_user = @sponsorship2.sponsor

      followed_user2 = @sponsorship3.sponsor
      viewer.follow(followed_user2)

      sponsors = @sponsorable.sponsors_visible_to(viewer, direction: :asc)

      assert_equal [unfollowed_user, followed_user1, followed_user2], sponsors
    end

    test "returns sponsors sorted by login when specified" do
      viewer = create(:user)

      sponsor_b = @sponsorship1.sponsor
      sponsor_b.update!(login: "BeautifulChocolateFountain")

      sponsor_a = @sponsorship2.sponsor
      sponsor_a.update!(login: "AsyncFluctuatingTree")

      sponsor_c = @sponsorship3.sponsor
      sponsor_c.update!(login: "CardinalFragilePickle")

      sponsors = @sponsorable.sponsors_visible_to(nil, order: GitHubSponsors::Types::SponsorOrder::Login,
        direction: :asc)

      assert_equal [sponsor_a, sponsor_b, sponsor_c], sponsors
    end

    test "returns sponsors sorted by reverse login when specified" do
      viewer = create(:user)

      sponsor_b = @sponsorship1.sponsor
      sponsor_b.update!(login: "BaldEggYolk")

      sponsor_a = @sponsorship2.sponsor
      sponsor_a.update!(login: "ArtificialTroubledLemon")

      sponsor_c = @sponsorship3.sponsor
      sponsor_c.update!(login: "CraftySoupedUpCaterpillar")

      sponsors = @sponsorable.sponsors_visible_to(nil, order: GitHubSponsors::Types::SponsorOrder::Login,
        direction: :desc)

      assert_equal [sponsor_c, sponsor_b, sponsor_a], sponsors
    end

    test "returns all sponsors for the user when viewer can see private sponsors" do
      @sponsorship3.update_columns(privacy_level: "private")

      sponsors = @sponsorable.reload.sponsors_visible_to(@sponsorable)

      assert_same_elements [@sponsorship1, @sponsorship2, @sponsorship3].map(&:sponsor_id), sponsors.map(&:id)
    end

    test "includes sponsor who made a one-time payment recently" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)

      sponsors = @sponsorable.reload.sponsors_visible_to(nil)

      assert_includes sponsors, sponsorship.sponsor, "should include recent one-time sponsor"
    end

    test "omits sponsor who made a one-time payment long ago" do
      sponsorship = create(:sponsorship, :expired, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)

      sponsors = @sponsorable.reload.sponsors_visible_to(nil)

      refute_includes sponsors, sponsorship.sponsor,
        "should not include one-time sponsor who did not recently sponsor"
    end

    test "returns sponsors filtered by single Sponsors tier when provided" do
      tier1, tier2 = @sponsors_listing.sponsors_tiers.first(2)

      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier1.id, privacy_level: "private")
      @sponsorship3.update_columns(subscribable_id: tier2.id)

      sponsorships_scope = Sponsorship.with_tier(tier1)

      sponsors = @sponsorable.reload.sponsors_visible_to(@sponsorable, sponsorships_scope: sponsorships_scope)

      assert_includes sponsors, @sponsorship1.sponsor
      assert_includes sponsors, @sponsorship2.sponsor
      refute_includes sponsors, @sponsorship3.sponsor
    end

    test "returns sponsors filtered by multiple Sponsors tiers" do
      tier1, tier2, tier3 = @sponsors_listing.sponsors_tiers

      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier2.id)
      @sponsorship3.update_columns(subscribable_id: tier3.id)

      sponsorships_scope = Sponsorship.with_tier([tier2, tier3])

      sponsors = @sponsorable.reload.sponsors_visible_to(nil, sponsorships_scope: sponsorships_scope)

      refute_includes sponsors, @sponsorship1.sponsor
      assert_includes sponsors, @sponsorship2.sponsor
      assert_includes sponsors, @sponsorship3.sponsor
    end

    test "returns only public sponsorships filtered by tier" do
      tier1, tier2 = @sponsors_listing.sponsors_tiers.first(2)

      @sponsorship1.update_columns(subscribable_id: tier1.id)
      @sponsorship2.update_columns(subscribable_id: tier1.id, privacy_level: "private")
      @sponsorship3.update_columns(subscribable_id: tier2.id)

      sponsorships_scope = Sponsorship.with_tier(tier1).privacy_public

      sponsors = @sponsorable.sponsors_visible_to(nil, sponsorships_scope: sponsorships_scope)

      assert_includes sponsors, @sponsorship1.sponsor
      refute_includes sponsors, @sponsorship2.sponsor
      refute_includes sponsors, @sponsorship3.sponsor
    end

    test "cannot filter to another sponsorable's tiers" do
      other_listing = @sponsorships_for_sponsor.first.sponsors_listing
      refute_equal other_listing, @sponsorable.sponsors_listing,
        "need two different Sponsors listings"
      other_tier = create(:sponsors_tier, :published, sponsors_listing: other_listing)
      sponsorships_scope = Sponsorship.with_tier(other_tier)

      assert_empty @sponsorable.sponsors_visible_to(@sponsorable, sponsorships_scope: sponsorships_scope)
    end

    test "omits spammy sponsor based on who the viewer is" do
      sponsorship = create(:sponsorship, :with_spammy_sponsor)
      spammy_sponsor = sponsorship.sponsor
      sponsorable = sponsorship.sponsorable

      assert_empty sponsorable.sponsors_visible_to(sponsorable),
        "should not return spammy sponsor for sponsorable viewer"
      assert_empty sponsorable.sponsors_visible_to(nil), "should not return spammy sponsor for anonymous viewer"
      assert_equal [spammy_sponsor], sponsorable.sponsors_visible_to(spammy_sponsor),
        "should return spammy sponsor when they are the viewer"
    end
  end

  context "#sponsoring_visible_to" do
    test "returns sponsored sponsorables for the user" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      sponsorship3.update_columns(privacy_level: "private")

      sponsoring = @sponsor.reload.sponsoring_visible_to(@sponsor)

      assert_includes sponsoring, sponsorship1.sponsorable
      assert_includes sponsoring, sponsorship2.sponsorable
      assert_includes sponsoring, sponsorship3.sponsorable
      assert_equal 3, sponsoring.count
    end

    test "returns ranked sponsorables for the viewer" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      viewer = create(:user)

      followed_user1 = sponsorship1.sponsorable
      viewer.follow(followed_user1)

      unfollowed_user = sponsorship2.sponsorable

      followed_user2 = sponsorship3.sponsorable
      viewer.follow(followed_user2)

      sponsorables = @sponsor.sponsoring_visible_to(viewer)

      assert_equal [followed_user2, followed_user1, unfollowed_user], sponsorables
      assert_equal sponsorables, @sponsor.async_sponsoring_visible_to(viewer).sync
    end

    test "returns ranked sponsorables in specified direction for the viewer" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      viewer = create(:user)

      followed_user1 = sponsorship1.sponsorable
      viewer.follow(followed_user1)

      unfollowed_user = sponsorship2.sponsorable

      followed_user2 = sponsorship3.sponsorable
      viewer.follow(followed_user2)

      sponsorables = @sponsor.sponsoring_visible_to(viewer, direction: :asc)

      assert_equal [unfollowed_user, followed_user1, followed_user2], sponsorables
      assert_equal sponsorables, @sponsor.async_sponsoring_visible_to(viewer, direction: :asc).sync
    end

    test "returns sponsorables sorted by login when specified" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      viewer = create(:user)

      sponsorable_b = sponsorship1.sponsorable
      sponsorable_b.update!(login: "Big")

      sponsorable_a = sponsorship2.sponsorable
      sponsorable_a.update!(login: "Ancient")

      sponsorable_c = sponsorship3.sponsorable
      sponsorable_c.update!(login: "Classy")

      sponsorables = @sponsor.sponsoring_visible_to(nil, order: GitHubSponsors::Types::SponsorableOrder::Login,
        direction: :asc)

      assert_equal [sponsorable_a, sponsorable_b, sponsorable_c].map(&:login), sponsorables.map(&:login)
      assert_equal sponsorables, @sponsor.async_sponsoring_visible_to(nil,
        order: GitHubSponsors::Types::SponsorableOrder::Login, direction: :asc).sync
    end

    test "returns sponsorables sorted by reverse login when specified" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      viewer = create(:user)

      sponsorable_b = sponsorship1.sponsorable
      sponsorable_b.update!(login: "Biscuit")

      sponsorable_a = sponsorship2.sponsorable
      sponsorable_a.update!(login: "Artichoke")

      sponsorable_c = sponsorship3.sponsorable
      sponsorable_c.update!(login: "Carrot")

      sponsorables = @sponsor.sponsoring_visible_to(nil, order: GitHubSponsors::Types::SponsorableOrder::Login,
        direction: :desc)

      assert_equal [sponsorable_c, sponsorable_b, sponsorable_a].map(&:login), sponsorables.map(&:login)
      assert_equal sponsorables, @sponsor.async_sponsoring_visible_to(nil,
        order: GitHubSponsors::Types::SponsorableOrder::Login, direction: :desc).sync
    end

    test "omits maintainer when the user sponsored them with a one-time payment long ago" do
      sponsorship = create(:sponsorship, :expired, sponsor: @sponsor, tier: @one_time_tier)
      sponsoring = @sponsor.reload.sponsoring_visible_to(@sponsor)
      refute_includes sponsoring, sponsorship.sponsorable
    end

    test "returns only publicly sponsored sponsorables for the user when no viewer is specified" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      sponsorship3.update_columns(privacy_level: "private")

      sponsoring_logins = @sponsor.reload.sponsoring_visible_to(nil).map(&:login)

      assert_includes sponsoring_logins, sponsorship1.sponsorable_login
      assert_includes sponsoring_logins, sponsorship2.sponsorable_login
      refute_includes sponsoring_logins, sponsorship3.sponsorable_login
      assert_equal 2, sponsoring_logins.count
    end

    test "returns only publicly sponsored sponsorables for the user when an unrelated viewer is specified" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      sponsorship3.update_columns(privacy_level: "private")
      rando = create(:user)

      sponsoring = @sponsor.reload.sponsoring_visible_to(rando)

      assert_includes sponsoring, sponsorship1.sponsorable
      assert_includes sponsoring, sponsorship2.sponsorable
      refute_includes sponsoring, sponsorship3.sponsorable
      assert_equal 2, sponsoring.count
    end

    test "includes privately sponsored sponsorables when viewed by the sponsor" do
      sponsorship1, sponsorship2, sponsorship3 = @sponsorships_for_sponsor
      sponsorship3.update_columns(privacy_level: "private")

      sponsoring = @sponsor.reload.sponsoring_visible_to(@sponsor)

      assert_same_elements [sponsorship1, sponsorship2, sponsorship3].map(&:sponsorable), sponsoring
    end

    # https://github.com/github/sponsors/issues/2790
    test "includes sponsorables where the sponsor is a linked org" do
      assert_equal @org_that_pays, @org_that_gets_credit.reload_sponsoring_linked_organization
      sponsorship = create(:sponsorship, sponsor: @org_that_pays)

      sponsoring = @org_that_gets_credit.sponsoring_visible_to(nil)

      assert_equal [sponsorship.sponsorable], sponsoring
    end

    test "includes directly sponsored sponsorables as well as sponsorables where the sponsor is a linked org" do
      linked_org_sponsorship = create(:sponsorship, sponsor: @org_that_pays)
      create(:billing_plan_subscription, user: @org_that_gets_credit)
      direct_sponsorship = create(:sponsorship, sponsor: @org_that_gets_credit)

      sponsoring = @org_that_gets_credit.reload.sponsoring_visible_to(nil)

      assert_same_elements [linked_org_sponsorship.sponsorable, direct_sponsorship.sponsorable], sponsoring
    end
  end

  context "#async_sponsor_exists_and_is_visible_to?" do
    test "true when public sponsor exists" do
      assert @sponsorable.async_sponsor_exists_and_is_visible_to?(@sponsorship1.sponsor_id, viewer: nil).sync
    end

    test "false when sponsor exists but specified tier is different from sponsorship tier" do
      refute_equal @sponsorship1.tier, @one_time_tier
      refute @sponsorable.async_sponsor_exists_and_is_visible_to?(@sponsorship1.sponsor_id, viewer: nil,
        tier_ids: @one_time_tier.id).sync
    end

    test "true when sponsor exists and specified tier is the sponsorship tier" do
      assert @sponsorable.async_sponsor_exists_and_is_visible_to?(@sponsorship1.sponsor_id, viewer: nil,
        tier_ids: @sponsorship1.subscribable_id).sync
    end

    test "true when private sponsor exists and viewer can see that" do
      private_sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable)
      assert @sponsorable.async_sponsor_exists_and_is_visible_to?(private_sponsorship.sponsor_id,
        viewer: @sponsorable).sync
      assert @sponsorable.async_sponsor_exists_and_is_visible_to?(private_sponsorship.sponsor_id,
        viewer: private_sponsorship.sponsor).sync
    end

    test "false when private sponsor exists and viewer cannot see that" do
      private_sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable)
      refute @sponsorable.async_sponsor_exists_and_is_visible_to?(private_sponsorship.sponsor_id, viewer: nil).sync
      refute @sponsorable.async_sponsor_exists_and_is_visible_to?(private_sponsorship.sponsor_id,
        viewer: @non_sponsor).sync
    end

    test "false when no sponsorship exists" do
      refute @sponsorable.async_sponsor_exists_and_is_visible_to?(@non_sponsor.id, viewer: nil).sync
      refute @sponsorable.async_sponsor_exists_and_is_visible_to?(@non_sponsor.id, viewer: @sponsorable).sync
      refute @sponsorable.async_sponsor_exists_and_is_visible_to?(@non_sponsor.id, viewer: @non_sponsor).sync
    end
  end

  context "#public_github_sponsor?" do
    test "returns false when user has no sponsored sponsorables" do
      refute_predicate @non_sponsor, :public_github_sponsor?
    end

    test "returns false with only private and active sponsorships" do
      Sponsorship.
        where(id: @sponsorships_for_sponsor.map(&:id)).
        update_all(privacy_level: "private")

      refute_predicate @sponsor.reload, :public_github_sponsor?
    end

    test "returns false with public but inactive sponsorships" do
      Sponsorship.
        where(id: @sponsorships_for_sponsor.map(&:id)).
        update_all(active: false)

      refute_predicate @sponsor.reload, :public_github_sponsor?
    end

    test "returns true with at least one public and active sponsorship" do
      sponsorship = @sponsorships_for_sponsor.first

      assert_predicate sponsorship, :active?
      assert_predicate sponsorship, :privacy_public?
      assert_predicate @sponsor, :public_github_sponsor?
    end
  end

  context "#sponsored_by_viewer?" do
    test "returns true if sponsorable is sponsored by a user" do
      assert @sponsorable.sponsored_by_viewer?(@sponsorship1.sponsor)
    end

    test "returns false if sponsorable is not sponsored by a user" do
      refute @sponsorable.sponsored_by_viewer?(@non_sponsor)
    end

    test "returns false for nil user" do
      refute @sponsorable.sponsored_by_viewer?(nil)
    end

    test "can be preloaded to avoid N+1s" do
      user = @sponsorship1.sponsor
      GitHub::PrefillAssociations.prefill_batch_method([@sponsorable], :sponsored_by_viewer?, user)

      assert_query_count 0 do
        @sponsorable.sponsored_by_viewer?(user)
      end
    end
  end

  context "#sponsoring_viewer?" do
    test "returns true if sponsor is sponsoring a sponsorable" do
      assert @sponsorship1.sponsor.sponsoring_viewer?(@sponsorable)
    end

    test "returns false if sponsor is not sponsoring a sponsorable" do
      refute @non_sponsor.sponsoring_viewer?(@sponsorable)
    end

    test "returns false for nil user" do
      refute @sponsorship1.sponsor.sponsoring_viewer?(nil)
    end

    test "can be preloaded to avoid N+1s" do
      viewer = @sponsorable
      sponsor = @sponsorship1.sponsor
      GitHub::PrefillAssociations.prefill_batch_method([sponsor], :sponsored_by_viewer?, viewer)

      assert_query_count 0 do
        @sponsorable.sponsored_by_viewer?(viewer)
      end
    end
  end

  context "#sponsor_exists_and_is_visible_to?" do
    test "returns false when viewer is not part of the private sponsorship" do
      sponsorship = create(:sponsorship, :private)
      refute sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: nil)

      rando = create(:user)
      refute sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: rando)
    end

    test "returns true when viewer is part of the private sponsorship" do
      sponsorship = create(:sponsorship, :private)
      assert sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: sponsorship.sponsor)

      assert sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: sponsorship.sponsorable)
    end

    test "returns true for admin of an org that receives a private sponsorship" do
      org = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, :private, sponsorable: org)
      org_admin = org.admins.first

      refute_nil org_admin
      assert org.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: org_admin)
    end

    test "returns true for member of an org that receives a private sponsorship" do
      org = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, :private, sponsorable: org)
      org_member = create(:user)
      org.add_member(org_member)

      assert org.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: org_member)
    end

    test "returns false for non-member of an org that receives a private sponsorship" do
      org = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, :private, sponsorable: org)
      rando = create(:user)

      refute org.sponsor_exists_and_is_visible_to?(sponsorship.sponsor,
        viewer: rando)
    end

    test "returns true for admin of an org that gives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      org_admin = org.admins.first

      refute_nil org_admin
      assert sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(org, viewer: org_admin)
    end

    test "returns true for member of an org that gives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      org_member = create(:user)
      org.add_member(org_member)

      assert sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(org, viewer: org_member)
    end

    test "returns false for non-member of an org that gives a private sponsorship" do
      sponsorship = create(:sponsorship, :private, :from_org)
      org = sponsorship.sponsor
      rando = create(:user)

      refute sponsorship.sponsorable.sponsor_exists_and_is_visible_to?(org, viewer: rando)
    end

    test "returns true for one-time sponsor who sponsored recently" do
      sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)

      assert @sponsorable.sponsor_exists_and_is_visible_to?(@sponsor, viewer: @sponsor)
    end

    test "returns false for one-time sponsor who sponsored long ago" do
      sponsorship = create(:sponsorship, :expired, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)

      refute @sponsorable.sponsor_exists_and_is_visible_to?(@sponsor, viewer: @sponsor)
    end
  end

  context "#sponsors_enabled_accounts" do
    test "returns the user themselves as well as orgs they admin" do
      user = create(:user, :verified, login: "userA")
      admined_org = create(:organization, admin: user, login: "adminedOrg")
      billing_managed_org = create(:organization, login: "billingManagedOrg")
      billing_managed_org.billing.add_manager(user, actor: billing_managed_org.admin)

      assert_same_elements [admined_org, user], user.sponsors_enabled_accounts,
        "should not include billing managed org"
    end
  end

  context "#any_not_banned_sponsors_listing_accounts?" do
    test "false without sponsors listing" do
      user = create(:user)
      org = create(:organization, admin: user)

      refute_predicate user, :any_not_banned_sponsors_listing_accounts?
      refute_predicate org, :any_not_banned_sponsors_listing_accounts?
    end

    test "false with banned sponsors listing" do
      @sponsors_listing.actor = @staff
      @sponsors_listing.ban!(banned_reason: "cuz")
      @org.sponsors_listing.actor = @staff
      @org.sponsors_listing.ban!(banned_reason: "cuz")

      refute_predicate @sponsorable, :any_not_banned_sponsors_listing_accounts?
      refute_predicate @org, :any_not_banned_sponsors_listing_accounts?
    end

    test "true with sponsors listing" do
      assert_predicate @sponsorable, :any_not_banned_sponsors_listing_accounts?
      assert_predicate @org, :any_not_banned_sponsors_listing_accounts?
    end

    test "returns true for org admin when org has listing but admin doesn't" do
      assert_nil @org.admin.sponsors_listing
      assert_predicate @org.admin, :any_not_banned_sponsors_listing_accounts?
    end
  end

  context "#sponsorship_match_ineligible_from_age_or_spamminess?" do
    test "returns true if user is spammy" do
      @sponsorable.update_columns(spammy: true, created_at: 2.months.ago)
      assert_predicate @sponsorable.reload, :spammy?
      assert_predicate @sponsorable, :sponsorship_match_ineligible_from_age_or_spamminess?
    end

    test "returns true if user is not older than 1 month" do
      @sponsorable.update_columns(created_at: 2.days.ago)
      refute_predicate @sponsorable.reload, :spammy?
      assert_predicate @sponsorable, :sponsorship_match_ineligible_from_age_or_spamminess?
    end

    test "returns false if user is not spammy and created longer than 1 month ago" do
      @sponsorable.update_columns(created_at: 2.months.ago)
      refute_predicate @sponsorable.reload, :spammy?
      refute_predicate @sponsorable, :sponsorship_match_ineligible_from_age_or_spamminess?
    end
  end

  context "#eligible_for_sponsorship_match?" do
    test "false if account was created less than one month ago" do
      @non_sponsor.update_columns(created_at: 3.days.ago)
      refute @non_sponsor.reload.eligible_for_sponsorship_match?(sponsorable: @sponsorable)
    end

    test "false if the account is spammy" do
      @non_sponsor.update_columns(spammy: true)
      refute @non_sponsor.reload.eligible_for_sponsorship_match?(sponsorable: @sponsorable)
    end

    test "false if match ban exists for sponsor and sponsorable" do
      @non_sponsor.update_columns(created_at: 2.months.ago)
      create(:sponsorship_match_ban, sponsor: @non_sponsor, sponsorable: @sponsorable)

      refute @non_sponsor.eligible_for_sponsorship_match?(sponsorable: @sponsorable)
    end

    test "true when user is over a month old and has a verified email" do
      @non_sponsor.update_columns(created_at: 2.months.ago)
      assert @non_sponsor.reload.eligible_for_sponsorship_match?(sponsorable: @sponsorable)
    end

    test "false when user has a published listing" do
      assert_predicate @sponsorable.reload.sponsors_listing, :approved?
      refute @sponsorable.eligible_for_sponsorship_match?(sponsorable: create(:user, :sponsorable))
    end

    test "true when user has a draft listing" do
      @sponsorable.update_columns(created_at: 2.months.ago)
      sponsors_listing = @sponsorable.sponsors_listing
      sponsors_listing.update_columns(
        state: SponsorsListing.state_value(:draft)
      )
      assert @sponsorable.reload.eligible_for_sponsorship_match?(sponsorable: create(:user, :sponsorable))
    end
  end

  context "last_one_time_payment_to" do
    test "returns the most recent one-time payment sponsors activity to a given sponsorable" do
      one_time_tier = create(:sponsors_tier, :one_time, :published)
      recurring_tier = create(:sponsors_tier, :recurring, :published)
      create(:sponsors_activity,
          :new_sponsorship,
          sponsor: @sponsor,
          sponsorable: @sponsorable,
          timestamp: 4.days.ago,
          sponsors_tier: one_time_tier
        )
      create(:sponsors_activity,
          :processing,
          sponsor: @sponsor,
          sponsorable: @sponsorable,
          sponsors_tier: recurring_tier
        )
      newest_one_time_sponsors_activity = create(:sponsors_activity,
        :processing,
        :one_time,
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        sponsors_tier: one_time_tier
      )

      assert_equal newest_one_time_sponsors_activity, @sponsor.last_one_time_payment_to(@sponsorable)
    end
  end

  context "#processing_one_time_payment_to?" do
    test "returns true if a one-time payment has been made in the last 2 days" do
      create(:sponsors_activity, :processing, :one_time, sponsor: @sponsor, sponsorable: @sponsorable)

      assert @sponsor.processing_one_time_payment_to?(@sponsorable)
    end

    test "returns false if a one-time payment has not been made in the last 2 days" do
      create(:sponsors_activity, :new_sponsorship, :one_time, sponsor: @sponsor, sponsorable: @sponsorable, timestamp: 3.days.ago)

      refute @sponsor.processing_one_time_payment_to?(@sponsorable)
    end
  end

  context "#sponsors_featured_description" do
    test "returns featured description from listing when it's set" do
      @sponsors_listing.update!(featured_description: "hey kind folks")
      assert_equal "hey kind folks", @sponsorable.reload.sponsors_featured_description
    end

    test "returns nil when user is not a member of Sponsors" do
      refute_predicate @non_sponsor, :sponsors_program_member?
      assert_nil @non_sponsor.sponsors_featured_description
    end
  end

  context "#sponsors_featured_disabled?" do
    test "true when user's Sponsors listing is in disabled featured state" do
      assert_equal "disabled", @sponsorable.sponsors_listing.featured_state
      assert_predicate @sponsorable, :sponsors_featured_disabled?
    end

    test "false when user's Sponsors listing is not in disabled featured state" do
      @sponsorable.sponsors_listing.update!(featured_state: "allowed")
      refute_predicate @sponsorable, :sponsors_featured_disabled?
    end

    test "false when user is not a Sponsors member" do
      refute_predicate @non_sponsor, :sponsors_program_member?
      refute_predicate @non_sponsor, :sponsors_featured_disabled?
    end
  end

  context "#indirect_sponsorships_from" do
    test "includes sponsorship when user is sponsored by one of the public orgs of the given user" do
      sponsorship = create(:sponsorship, sponsor: @org_sponsor, sponsorable: @sponsorable)
      assert_equal [sponsorship], @sponsorable.indirect_sponsorships_from(@public_org_member,
        viewer: @sponsorable)
    end

    test "omits inactive sponsorship" do
      create(:sponsorship, :inactive, sponsor: @org_sponsor,
        sponsorable: @sponsorable)
      assert_empty @sponsorable.indirect_sponsorships_from(@public_org_member,
        viewer: @sponsorable)
    end

    # https://github.com/github/sponsors/issues/1911
    test "omits sponsorship from org the viewer belongs to when the user doesn't belong to it" do
      sponsorship = create(:sponsorship, :from_org)
      org = sponsorship.sponsor
      org_member = sponsorship.sponsorable
      org.add_member(org_member)
      org.publicize_member(org_member)

      refute org.member?(@non_sponsor),
        "need a user who does not belong to the sponsoring org"
      assert_empty org_member.indirect_sponsorships_from(@non_sponsor,
        viewer: org_member)
    end

    test "omits sponsorship when user is sponsored by one of the orgs of the given user but org membership is not visible to viewer" do
      create(:sponsorship, sponsor: @org_sponsor, sponsorable: @sponsorable)
      assert_empty @sponsorable.indirect_sponsorships_from(@private_org_member,
        viewer: @sponsorable)
    end

    test "omits private sponsorship for anonymous viewer" do
      create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: @sponsorable)
      assert_empty @sponsorable.indirect_sponsorships_from(@public_org_member, viewer: nil)
    end

    test "omits private sponsorship when viewer is not part of the sponsorship" do
      create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: @sponsorable)
      assert_empty @sponsorable.indirect_sponsorships_from(@public_org_member, viewer: @non_sponsor)
    end

    test "includes private sponsorship when viewed by the sponsored user" do
      sponsorship = create(:sponsorship, :private, sponsor: @org_sponsor,
        sponsorable: @sponsorable)
      assert_equal [sponsorship], @sponsorable
        .indirect_sponsorships_from(@public_org_member, viewer: @sponsorable)
    end

    test "omits private sponsorship when viewed by the sponsored user when org membership is private" do
      create(:sponsorship, :private, sponsor: @org_sponsor, sponsorable: @sponsorable)
      assert_empty @sponsorable.indirect_sponsorships_from(@private_org_member, viewer: @sponsorable)
    end

    test "includes private sponsorship when viewed by the sponsored user, org membership is private, but sponsored user also belongs to the org" do
      sponsorship = create(:sponsorship, :private, sponsor: @org_sponsor,
        sponsorable: @sponsorable)
      @org_sponsor.add_member(@sponsorable)

      assert_equal [sponsorship], @sponsorable
        .indirect_sponsorships_from(@private_org_member, viewer: @sponsorable)
    end

    test "omits sponsorship when user is not sponsored by one of the orgs that the given user belongs to" do
      assert_empty @sponsorable.indirect_sponsorships_from(@public_org_member,
        viewer: @sponsorable)
    end

    test "omits sponsorship when it's a direct sponsorship from the given user" do
      assert_empty @sponsorable.indirect_sponsorships_from(@sponsorship1.sponsor,
        viewer: @sponsorable)
    end
  end

  context "approved_sponsors_listing relation" do
    test "nil when Sponsors listing is not approved" do
      listing = create(:sponsors_listing, :draft)
      assert_nil listing.sponsorable.approved_sponsors_listing
    end

    test "returns approved Sponsors listing for the user" do
      assert_equal @sponsors_listing, @sponsorable.approved_sponsors_listing
    end

    test "nil when user has no Sponsors listing" do
      assert_nil @non_sponsor.approved_sponsors_listing
    end
  end

  context "#sponsors_contact_email" do
    test "returns email record for listing when set" do
      email = create(:user_email, :verified, user: @sponsorable)
      @sponsors_listing.update!(contact_email_id: email.id)
      assert_equal email, @sponsorable.sponsors_contact_email
    end

    test "returns nil when listing has an invalid email ID" do
      @sponsors_listing.contact_email.delete
      assert_nil @sponsorable.sponsors_contact_email
    end

    test "returns nil when no email is set on listing" do
      @sponsors_listing.update_attribute(:contact_email_id, nil)
      assert_nil @sponsorable.sponsors_contact_email
    end

    test "returns nil for user who is not a Sponsors member" do
      assert_nil @non_sponsor.sponsors_contact_email
    end
  end

  context "#within_sponsors_stripe_account_limit?" do
    test "true when user has no Sponsors listing" do
      assert_predicate @non_sponsor, :within_sponsors_stripe_account_limit?
    end

    test "true when user's Sponsors listing has no Stripe accounts" do
      assert_empty @sponsors_listing.stripe_connect_accounts
      assert_predicate @sponsors_listing.sponsorable, :within_sponsors_stripe_account_limit?
    end

    test "true when user's Sponsors listing has fewer than the max allowed Stripe accounts" do
      refute_empty @fiscal_host_listing.stripe_connect_accounts
      assert_predicate @fiscal_host_listing.sponsorable, :within_sponsors_stripe_account_limit?
    end

    test "false when user's Sponsors listing is at the limit of Stripe accounts" do
      refute_empty @fiscal_host_listing.stripe_connect_accounts
      Billing::StripeConnect::Account.stub_const(:MAX_ACCOUNTS_PER_SPONSORS_LISTING, 1) do
        refute_predicate @fiscal_host_listing.sponsorable, :within_sponsors_stripe_account_limit?
      end
    end
  end

  context "sponsorship_repositories_as_sponsor association" do
    test "deletes sponsorship repo records when sponsor is destroyed" do
      sponsorship_repo1 = create(:sponsorship_repository)
      user = sponsorship_repo1.sponsor
      sponsorship_repo2 = create(:sponsorship_repository, sponsor: user)
      other_sponsorship_repo = create(:sponsorship_repository)

      assert_difference(-> { SponsorshipRepository.count }, -2) do
        user.destroy!
      end

      refute SponsorshipRepository.exists?(sponsorship_repo1.id)
      refute SponsorshipRepository.exists?(sponsorship_repo2.id)
      assert SponsorshipRepository.exists?(other_sponsorship_repo.id)
    end
  end

  context "#eligible_for_nudging_to_sign_up_for_sponsors?" do
    test "can still return true for user with a draft Sponsors listing" do
      user = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago - 1.day) do
        create(:user, time_zone_name: Sponsors::TimeZone.supported_names.first)
      end
      create(:profile, user: user, name: "K.K. Slider")
      create(:repository, owner: user)
      create(:issue, user: user)
      assert_predicate user, :eligible_for_nudging_to_sign_up_for_sponsors?

      create(:sponsors_listing, :draft, sponsorable: user)
      assert_predicate user.reload, :eligible_for_nudging_to_sign_up_for_sponsors?
    end if GitHub.sponsors_enabled?

    test "returns false when the user has no public repositories" do
      user = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago - 1.day) do
        create(:user, time_zone_name: Sponsors::TimeZone.supported_names.first)
      end
      create(:profile, user: user, name: "Tom Nook")
      create(:issue, user: user)
      refute_predicate user, :eligible_for_nudging_to_sign_up_for_sponsors?
    end

    test "returns false when the user has no public contributions" do
      user = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago - 1.day) do
        create(:user, time_zone_name: Sponsors::TimeZone.supported_names.first)
      end
      create(:profile, user: user, name: "Isabelle")
      create(:repository, owner: user)
      refute_predicate user, :eligible_for_nudging_to_sign_up_for_sponsors?
    end

    test "returns false when a user who would otherwise be eligible has been transformed into an org" do
      sponsorable = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago - 1.day) do
        create(:user, time_zone_name: Sponsors::TimeZone.supported_names.first)
      end
      create(:profile, user: sponsorable, name: "Meh Meh")

      public_repo = create(:repository, owner: sponsorable)
      create(:commit_contribution, user: sponsorable, repository: public_repo,
        commit_count: 1, committed_date: 6.months.ago)
      create(:issue, user: sponsorable)

      new_org_owner = create :user
      Organization.transform! sponsorable, new_org_owner
      sponsorable = Organization.find(sponsorable.id)

      refute_predicate sponsorable, :eligible_for_nudging_to_sign_up_for_sponsors?
    end

    test "returns false when the user signed up for GitHub after our Sponsors auto-ban cutoff" do
      user = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago + 1.day) do
        create(:user, time_zone_name: Sponsors::TimeZone.supported_names.first)
      end
      create(:profile, user: user, name: "Gracie Grace")
      create(:repository, owner: user)
      create(:issue, user: user)
      refute_predicate user, :eligible_for_nudging_to_sign_up_for_sponsors?
    end

    test "returns false when the user lacks a time zone" do
      user = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago - 1.day) do
        create(:user, time_zone_name: nil)
      end
      create(:profile, user: user, name: "Resetti")
      create(:repository, owner: user)
      create(:issue, user: user)
      refute_predicate user, :eligible_for_nudging_to_sign_up_for_sponsors?
    end

    test "returns false when the user has not customized their profile" do
      user = travel_to(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago - 1.day) do
        create(:user, time_zone_name: Sponsors::TimeZone.supported_names.first)
      end
      create(:repository, owner: user)
      create(:issue, user: user)
      refute_predicate user, :eligible_for_nudging_to_sign_up_for_sponsors?
    end
  end

  context "SponsorsActivity association" do
    test "keep sponsor_id when sponsor user is destroyed" do
      activity = create(:sponsors_activity)

      activity.sponsor.destroy

      refute_nil activity.reload.sponsor_id
    end

    test "destroys activity when sponsorable user is destroyed" do
      activity = create(:sponsors_activity)

      activity.sponsorable.destroy

      assert_nil SponsorsActivity.find_by(id: activity.id)
    end
  end

  context "#potential_sponsor_accounts" do
    test "orders user first, then owned and billing managed organizations alphabetically by login" do
      user = create(:user, login: "billg-#{Faker::Number.number(digits: 10)}")
      first_org = create(:organization, admin: user, login: "acme-#{Faker::Number.number(digits: 10)}")
      third_org = create(:organization, admin: user, login: "initech-#{Faker::Number.number(digits: 10)}")
      second_org = create(:organization, admin: user, login: "hooli-#{Faker::Number.number(digits: 10)}")
      fourth_org = create(:organization, login: "pied-piper-#{Faker::Number.number(digits: 10)}")
      fourth_org.billing.add_manager(user, actor: fourth_org.admins.first)

      assert_equal [user, first_org, second_org, third_org, fourth_org],
        user.potential_sponsor_accounts
    end
  end

  context "#sponsors_stripe_business_type" do
    test "returns individual for users" do
      assert_equal "individual", build(:user).sponsors_stripe_business_type
    end

    test "returns company for users" do
      assert_equal "company", build(:organization).sponsors_stripe_business_type
    end
  end

  context "#can_skip_sponsorship_proration?" do
    test "returns false if sponsor has blank bill_cycle_day" do
      @sponsor.customer.update!(bill_cycle_day: 0)

      assert_equal @sponsor.reload.customer_bill_cycle_day_for_sponsorships, 0
      refute_predicate @sponsor, :can_skip_sponsorship_proration?
    end

    test "returns false if sponsor is on yearly plan" do
      @sponsor.update!(plan_duration: User::BillingDependency::YEARLY_PLAN)

      assert_predicate @sponsor.reload, :yearly_plan?
      refute_predicate @sponsor, :can_skip_sponsorship_proration?
    end

    test "returns false if sponsor has no plan" do
      @sponsor.sponsors_plan_subscription.destroy!

      assert_predicate @sponsor.reload.sponsors_plan_subscription, :blank?
      refute_predicate @sponsor, :can_skip_sponsorship_proration?
    end

    test "returns false if sponsor has no zuora subscription" do
      @sponsor.sponsors_plan_subscription.update!(
        zuora_subscription_id: nil,
        zuora_subscription_number: nil,
      )

      refute_predicate @sponsor, :can_skip_sponsorship_proration?
    end

    test "returns true for sponsor with a Zuora subscription and bill cycle day" do
      assert_predicate @sponsor.sponsors_plan_subscription, :zuora_subscription?
      assert_predicate @sponsor.customer_bill_cycle_day_for_sponsorships, :positive?

      assert_predicate @sponsor, :can_skip_sponsorship_proration?
    end

    test "returns true for org with a Zuora subscription and bill cycle day" do
      Customer.any_instance.stubs(:bill_cycle_day).returns(1)
      Billing::PlanSubscription.any_instance.stubs(:zuora_subscription_number).returns("123")

      assert_predicate @org_sponsor, :organization?
      assert_predicate @org_sponsor, :can_skip_sponsorship_proration?
    end
  end

  context "#first_time_sponsor?" do
    test "returns true for users without any sponsorships" do
      user = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
      assert_predicate user, :first_time_sponsor?
    end

    test "returns true for orgs without any sponsorships" do
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      assert_predicate org, :first_time_sponsor?
    end

    test "returns true for users with a single sponsorship when it's excluded" do
      user = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
      sponsorship = create(:sponsorship, sponsor: user)

      assert user.first_time_sponsor?(new_sponsorship: sponsorship)
    end

    test "returns true for orgs with a single sponsorship when it's excluded" do
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      sponsorship = create(:sponsorship, sponsor: org)

      assert org.first_time_sponsor?(new_sponsorship: sponsorship)
    end

    test "returns true for orgs with a single linked sponsorship when it's excluded" do
      linked_org = create(:organization)
      sponsoring_org = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))

      create(:organization_profile,
        organization: linked_org,
        sponsoring_linked_organization: sponsoring_org)

      sponsorship = create(:sponsorship, sponsor: sponsoring_org)

      assert linked_org.first_time_sponsor?(new_sponsorship: sponsorship)
    end

    test "returns false for users with a single sponsorship when it's included" do
      user = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
      create(:sponsorship, sponsor: user)

      refute_predicate user, :first_time_sponsor?
    end

    test "returns false for orgs with a single sponsorship when it's included" do
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:sponsorship, sponsor: org)

      refute_predicate org, :first_time_sponsor?
    end

    test "returns false for orgs with a single linked sponsorship when it's included" do
      linked_org = create(:organization)
      sponsoring_org = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))

      create(:organization_profile,
        organization: linked_org,
        sponsoring_linked_organization: sponsoring_org)

      create(:sponsorship, sponsor: sponsoring_org)

      refute_predicate linked_org, :first_time_sponsor?
    end

    test "returns false for users with multiple sponsorships" do
      user = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
      sponsorships = create_list(:sponsorship, 2, sponsor: user)

      refute user.first_time_sponsor?(new_sponsorship: sponsorships.first)
    end

    test "returns false for orgs with multiple sponsorships" do
      org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      sponsorships = create_list(:sponsorship, 2, sponsor: org)

      refute org.first_time_sponsor?(new_sponsorship: sponsorships.first)
    end

    test "returns false for orgs with multiple linked sponsorships" do
      linked_org = create(:organization)
      sponsoring_org = create(:credit_card_org,
        plan_subscription: create(:billing_plan_subscription))

      create(:organization_profile,
        organization: linked_org,
        sponsoring_linked_organization: sponsoring_org)

      sponsorships = create_list(:sponsorship, 2, sponsor: sponsoring_org)

      refute linked_org.first_time_sponsor?(new_sponsorship: sponsorships.first)
    end
  end

  context "#first_time_sponsorable?" do
    test "returns true for users without any sponsorships where they're the maintainer" do
      assert_predicate @sponsorable_no_sponsors, :first_time_sponsorable?
    end

    test "returns true for orgs without any sponsorships where they're the maintainer" do
      assert_predicate @org, :first_time_sponsorable?
    end

    test "returns true for users with a single sponsorship when it's excluded" do
      sponsorship = create(:sponsorship, sponsorable: @sponsorable_no_sponsors)

      assert @sponsorable_no_sponsors.first_time_sponsorable?(new_sponsorship: sponsorship)
    end

    test "returns true for orgs with a single sponsorship when it's excluded" do
      sponsorship = create(:sponsorship, sponsorable: @org)

      assert @org.first_time_sponsorable?(new_sponsorship: sponsorship)
    end

    test "returns false for users with a single sponsorship when it's included" do
      create(:sponsorship, sponsorable: @sponsorable_no_sponsors)

      refute_predicate @sponsorable_no_sponsors, :first_time_sponsorable?
    end

    test "returns false for orgs with a single sponsorship when it's included" do
      create(:sponsorship, sponsorable: @org)

      refute_predicate @org, :first_time_sponsorable?
    end

    test "returns false for users with multiple sponsorships" do
      sponsorships = create_list(:sponsorship, 2, sponsorable: @sponsorable_no_sponsors)

      refute @sponsorable_no_sponsors.first_time_sponsorable?(new_sponsorship: sponsorships.first)
    end

    test "returns false for orgs with multiple sponsorships" do
      sponsorships = create_list(:sponsorship, 2, sponsorable: @org)

      refute @org.first_time_sponsorable?(new_sponsorship: sponsorships.first)
    end
  end

  context "#needs_personal_profile?" do
    test "true for user when sponsorable doesn't have a account_screening_profile" do
      assert @sponsorable.needs_personal_profile?
    end

    test "false for when user has an account_screening_profile" do
      create(:account_screening_profile, owner: @sponsorable)

      refute @sponsorable.needs_personal_profile?
    end

    test "false for organization" do
      refute @org.needs_personal_profile?
    end
  end

  context "#sponsors_business_tax_identifier_at" do
    test "nil for user without any tax identifiers" do
      assert_nil @org.sponsors_business_tax_identifier_at(DateTime.now)
    end

    test "returns identifiers at a point in time" do
      travel_to "2023-11-14"
      previous_identifier = travel_to(1.week.ago) { create(:sponsors_business_tax_identifier, user: @org) }
      current_identifier = create(:sponsors_business_tax_identifier, user: @org)

      assert_equal current_identifier, @org.sponsors_business_tax_identifier_at(DateTime.now)
      assert_equal(
        previous_identifier,
        @org.sponsors_business_tax_identifier_at(current_identifier.created_at - 1.second)
      )
      assert_nil @org.sponsors_business_tax_identifier_at(previous_identifier.created_at - 1.second)
    end
  end

  context "#earliest_sponsorship_date_as_sponsor" do
    test "returns earliest paid sponsorship date for a user" do
      sponsorship = travel_to("2021-11-13") { create(:sponsorship, :paid, sponsor: @sponsor) }
      travel_to "2023-11-13"

      result = @sponsor.earliest_sponsorship_date_as_sponsor

      refute_nil result
      assert_in_delta sponsorship.created_at, result, 1.minute
    end

    test "returns nil when user only has unpaid sponsorships" do
      unpaid_sponsorship = create(:sponsorship, paid_at: nil)
      sponsor = unpaid_sponsorship.sponsor
      assert_nil sponsor.earliest_sponsorship_date_as_sponsor
    end

    test "returns earliest paid sponsorship date for a non-invoiced org" do
      sponsorship = travel_to("2021-11-13") { create(:sponsorship, :paid, sponsor: @org_sponsor) }
      travel_to "2023-11-13"

      result = @org_sponsor.earliest_sponsorship_date_as_sponsor

      refute_nil result
      assert_in_delta sponsorship.created_at, result, 1.minute
    end

    test "returns earliest paid sponsorship date for a linked org" do
      sponsorship = travel_to("2021-11-13") { create(:sponsorship, :paid, sponsor: @org_that_pays) }
      travel_to "2023-11-13"

      result = @org_that_gets_credit.earliest_sponsorship_date_as_sponsor

      refute_nil result
      assert_in_delta sponsorship.created_at, result, 1.minute
    end

    test "returns earliest sponsorship date for an invoiced org whose first sponsorship used Zuora" do
      sponsorship = travel_to("2021-11-13") do
        create(:sponsorship, :sponsors_invoiced, :with_billing_transaction_and_line_item, sponsor: @invoiced_org)
      end
      travel_to "2023-11-13"

      result = @invoiced_org.earliest_sponsorship_date_as_sponsor

      refute_nil result
      assert_in_delta sponsorship.created_at, result, 1.minute
    end

    test "returns earliest sponsorship date for an invoiced org whose first sponsorship did not use Zuora" do
      sponsorship = travel_to(1.month.ago) { create(:sponsorship, :invoiced) }
      org = sponsorship.sponsor

      result = org.earliest_sponsorship_date_as_sponsor

      refute_nil result
      # The sponsorship needs to be reloaded to avoid daylight savings/time zone issues during time comparison.
      # See: https://github.com/github/github/pull/249983#issuecomment-1353465962
      #
      # When records are set to a particular `created_at` that lands on DST the time is shifted by 1 hour
      # when it is loaded rom the database. This caused an issue since the `sponsorship.created` in the setup phase
      # of this test is not loaded from the database, but the `result` is. To make sure the times
      # match up, we can reload the `sponsorship` record to make sure the time zone/DST handling is the same
      # and fix date specific failures.
      assert_in_delta sponsorship.reload.created_at, result, 1.minute
    end
  end

  context "#sponsors_bio_html" do
    test "returns the listing's short description as html" do
      user = create(:user, :sponsorable)
      user.sponsors_listing.short_description = "My Sponsors bio"
      user.profile_bio = "My profile bio"

      assert_equal "<p>My Sponsors bio</p>", user.sponsors_bio_html
    end

    test "falls back to profile bio if the listing does not have a short description" do
      user = create(:user, :sponsorable)
      user.sponsors_listing.short_description = ""
      user.profile_bio = "My profile bio"

      assert_equal "<div>My profile bio</div>", user.sponsors_bio_html
    end

    test "falls back to profile bio if user does not have a Sponsors listing" do
      user = create(:user)
      user.profile_bio = "My profile bio"

      assert_equal "<div>My profile bio</div>", user.sponsors_bio_html
    end
  end

  context "#alert_sponsors_listing_time_zone_changed" do
    test "does nothing when time_zone_name has not been updated" do
      SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

      sponsorable = create(:user)
      listing = create(:sponsors_listing, sponsorable: sponsorable)
      metadata = listing.stafftools_metadata

      assert_nil metadata.sponsorable_time_zone_name
      sponsorable.update!(wants_email: false)
      assert_nil metadata.reload.sponsorable_time_zone_name
    end

    test "does nothing when time_zone_name gets updated with the same value" do
      sponsorable = create(:user, time_zone_name: "Pacific Time (US & Canada)")
      listing = create(:sponsors_listing, sponsorable: sponsorable)
      metadata = listing.stafftools_metadata

      assert_equal "Pacific Time (US & Canada)", metadata.sponsorable_time_zone_name

      SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never
      sponsorable.update!(time_zone_name: "Pacific Time (US & Canada)")

      assert_equal "Pacific Time (US & Canada)", metadata.reload.sponsorable_time_zone_name
    end

    test "updates time_zone_name on stafftools when the user time zone has been updated" do
      sponsorable = create(:user, time_zone_name: "Pacific Time (US & Canada)")
      listing = create(:sponsors_listing, sponsorable: sponsorable)
      metadata = listing.stafftools_metadata

      assert_equal "Pacific Time (US & Canada)", metadata.sponsorable_time_zone_name

      sponsorable.update!(time_zone_name: "Africa/Asmara")
      assert_equal "Africa/Asmara", metadata.reload.sponsorable_time_zone_name
    end
  end

  context "#sponsors_plan_duration" do
    test "returns yearly for yearly billed org" do
      org = create(:organization, plan_duration: User::BillingDependency::YEARLY_PLAN)

      assert_equal User::BillingDependency::YEARLY_PLAN, org.sponsors_plan_duration
    end

    test "returns monthly for monthly billed user" do
      user = create(:user, plan_duration: User::BillingDependency::MONTHLY_PLAN)

      assert_equal User::BillingDependency::MONTHLY_PLAN, user.sponsors_plan_duration
    end

    test "returns monthly for Zuora-invoiced Org that otherwise pays yearly" do
      invoiced_org = create(:invoiced_org, :sponsors_invoiced)

      assert_equal User::BillingDependency::YEARLY_PLAN, invoiced_org.plan_duration, "Everything but sponsorships are paid yearly"
      assert_equal User::BillingDependency::MONTHLY_PLAN, invoiced_org.sponsors_plan_duration, "Sponsorships are paid monthly"
    end
  end

  context "#next_sponsors_billing_date" do
    test "returns billed_on for User if billed_on is after today" do
      @sponsor.update_attribute :billed_on, GitHub::Billing.timezone.local(2016, 8, 10).to_billing_date

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-08-10", @sponsor.next_sponsors_billing_date.strftime("%F")
      end
    end

    test "returns billed_on for non-Zuora-invoiced Org if billed_on is after today" do
      @org_sponsor.update_attribute :billed_on, GitHub::Billing.timezone.local(2016, 8, 10).to_billing_date

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-08-10", @org_sponsor.next_sponsors_billing_date.strftime("%F")
      end
    end

    test "returns date on bill cycle day for Zuora-invoiced Org if today is before the bill cycle day" do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      org.sponsors_customer.update_columns(bill_cycle_day: 25)

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-07-25", org.next_sponsors_billing_date.strftime("%F")
      end
    end

    test "returns end of next month for Zuora-invoiced Org if today is after the bill cycle day (when not enough days in month)" do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      org.sponsors_customer.update_columns(bill_cycle_day: 30)

      travel_to(GitHub::Billing.timezone.local(2017, 1, 31)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2017-02-28", org.next_sponsors_billing_date.strftime("%F")
      end
    end

    test "returns today for Zuora-invoiced Org if bill cycle day isn't set" do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      org.sponsors_customer.update_columns(bill_cycle_day: 0)

      travel_to(GitHub::Billing.timezone.local(2016, 7, 10)) do
        # NB: using billing_dependency's version, defaults to today with no subscription
        assert_equal "2016-07-10", org.next_sponsors_billing_date.strftime("%F")
      end
    end
  end

  context "#yearly_sponsors_plan?" do
    test "true for user billed yearly" do
      user = create(:user, plan_duration: User::BillingDependency::YEARLY_PLAN)

      assert_predicate user, :yearly_sponsors_plan?
    end

    test "false for user billed monthly" do
      user = create(:user, plan_duration: User::BillingDependency::MONTHLY_PLAN)

      refute_predicate user, :yearly_sponsors_plan?
    end

    test "false for Zuora-invoiced Org that otherwise pays yearly" do
      invoiced_org = create(:invoiced_org, :sponsors_invoiced)

      assert_predicate invoiced_org, :yearly_plan?
      refute_predicate invoiced_org, :yearly_sponsors_plan?
    end
  end

  context "#formatted_next_sponsors_billing_date" do
    test "omits year when plan duration is monthly" do
      travel_to GitHub::Billing.timezone.local(2022, 9, 19) do
        sponsor = create(:credit_card_user,
          plan_duration: User::BillingDependency::MONTHLY_PLAN,
        )

        assert_equal "September 19", sponsor.formatted_next_sponsors_billing_date
      end
    end

    test "includes year when plan duration is yearly" do
      travel_to GitHub::Billing.timezone.local(2022, 9, 19) do
        sponsor = create(:credit_card_user,
          plan_duration: User::BillingDependency::YEARLY_PLAN,
        )

        assert_equal "September 19, 2022", sponsor.formatted_next_sponsors_billing_date
      end
    end

    test "uses sponsors-specific billing date" do
      travel_to GitHub::Billing.timezone.local(2022, 9, 19) do
        sponsor = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        sponsor.sponsors_customer.update_columns(bill_cycle_day: 25)

        assert_equal "September 25", sponsor.formatted_next_sponsors_billing_date
      end
    end
  end

  context "#trust_level_as_sponsor" do
    test "returns untrusted for account less than 6 months old" do
      user = build(:user)
      user.created_at = 4.months.ago

      assert_predicate user.trust_level_as_sponsor, :untrusted?
    end

    test "return neutral for account between 6 months and a year old" do
      user = build(:user)
      user.created_at = 8.months.ago

      assert_predicate user.trust_level_as_sponsor, :neutral?
    end

    test "returns trusted for account more than a year old" do
      user = build(:user)
      user.created_at = 14.months.ago

      assert_predicate user.trust_level_as_sponsor, :trusted?
    end
  end

  context "#trust_level_as_sponsorable" do
    test "returns untrusted for account less than 6 months old" do
      user = build(:user)
      user.created_at = 4.months.ago

      assert_predicate user.trust_level_as_sponsorable, :untrusted?
    end

    test "return neutral for account between 6 months and a year old" do
      user = build(:user)
      user.created_at = 8.months.ago

      assert_predicate user.trust_level_as_sponsorable, :neutral?
    end

    test "returns trusted for account more than a year old" do
      user = build(:user)
      user.created_at = 14.months.ago

      assert_predicate user.trust_level_as_sponsorable, :trusted?
    end
  end

  context "#should_pay_fees_at_sponsorship_payment_time?" do
    test "returns false for users" do
      user = build(:user)
      refute_predicate user, :should_pay_fees_at_sponsorship_payment_time?
    end

    test "returns false for invoiced orgs" do
      invoiced_org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      refute_predicate invoiced_org, :should_pay_fees_at_sponsorship_payment_time?
    end

    test "returns true for credit card orgs" do
      cc_org = create(:credit_card_org)
      assert_predicate cc_org, :should_pay_fees_at_sponsorship_payment_time?
    end
  end

  context "#sponsorable_via_patreon?" do
    test "true if user is sponsorable, has a valid Patreon tier, `enabled_as_sponsorable` is true" do
      spu = create(:sponsors_patreon_user, :with_tier, user: @sponsorable, enabled_as_sponsorable: true)
      assert_predicate spu, :any_valid_patreon_tiers?

      assert_predicate @sponsorable, :sponsorable_via_patreon?
    end

    test "false if `enabled_as_sponsorable` is false" do
      spu = create(:sponsors_patreon_user, :with_tier, user: @sponsorable, enabled_as_sponsorable: false)
      assert_predicate spu, :any_valid_patreon_tiers?

      refute_predicate @sponsorable, :sponsorable_via_patreon?
    end

    test "false if user is not sponsorable" do
      refute_predicate @sponsor, :sponsorable?, "need a non-sponsorable user"
      spu = create(:sponsors_patreon_user, :with_tier, user: @sponsor)
      assert_predicate spu, :any_valid_patreon_tiers?

      refute_predicate @sponsor, :sponsorable_via_patreon?
    end

    test "false if user does not have a Patreon user record" do
      refute SponsorsPatreonUser.exists?(user_id: @sponsorable.id), "need user to not have a SponsorsPatreonUser"

      refute_predicate @sponsorable, :sponsorable_via_patreon?
    end

    test "false if user does not any valid Patreon tier" do
      spu = create(:sponsors_patreon_user, user: @sponsorable)
      refute_predicate spu, :any_valid_patreon_tiers?, "need user to not have any valid Patreon tiers"

      refute_predicate @sponsorable, :sponsorable_via_patreon?
    end
  end

  context "#sponsors_prorated_by_default?" do
    test "returns true for user" do
      assert_predicate @sponsor, :sponsors_prorated_by_default?
    end
  end
end if GitHub.sponsors_enabled?
