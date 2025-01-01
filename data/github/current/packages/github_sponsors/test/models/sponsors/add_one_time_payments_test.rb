# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::AddOneTimePaymentsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @sponsorable1_listing = create(:sponsors_listing, :approved_with_only_custom_amounts,
      sponsorable_login: "sponsorable-the-first")
    @sponsorable1 = @sponsorable1_listing.sponsorable
    @sponsorable2_listing = create(:sponsors_listing, :approved_with_only_custom_amounts, :for_org,
      sponsorable_login: "org-sponsorable")
    @sponsorable2 = @sponsorable2_listing.sponsorable
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    GitHub.flipper[:sponsors_pending_sponsorships].disable
  end

  test "does not enqueue a job to email sponsors if sponsorship's state is active_test when FF enabled" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    sponsor.enable_feature(:sponsors_pending_sponsorships)

    assert_no_enqueued_jobs(only: SendPendingSponsorshipEmailJob) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        state: :active_test,
      )
    end
  end

  test "creates multiple sponsorships from a user and synchronizes the Sponsors-specific plan subscription once" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        privacy_level: "private",
        receive_email: true,
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_empty result.errors

    sponsorship1 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable1.id }
    refute_nil sponsorship1
    assert_equal 1_00, sponsorship1.monthly_price_in_cents
    assert_equal sponsor, sponsorship1.sponsor
    assert_equal @sponsorable1, sponsorship1.sponsorable
    refute_predicate sponsorship1, :recurring_payment?
    assert_predicate sponsorship1, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship1, :privacy_private?
    assert_predicate sponsorship1, :active?
    assert_equal plan_sub, sponsorship1.subscription_item.plan_subscription

    sponsorship2 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
    refute_nil sponsorship2
    assert_equal 2_00, sponsorship2.monthly_price_in_cents
    assert_equal sponsor, sponsorship2.sponsor
    assert_equal @sponsorable2, sponsorship2.sponsorable
    refute_predicate sponsorship2, :recurring_payment?
    assert_predicate sponsorship2, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship2, :privacy_private?
    assert_predicate sponsorship2, :active?
    assert_equal plan_sub, sponsorship2.subscription_item.plan_subscription
  end

  test "calls the given after-payment lambda" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    successful_logins = []

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        privacy_level: "private",
        receive_email: true,
        after_payment_hook: ->(login) { successful_logins << login },
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_equal [@sponsorable1.login, @sponsorable2.login], successful_logins
    assert_empty result.errors
    refute_nil result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable1.id }
    refute_nil result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
  end

  test "creates multiple sponsorships from an org as the billing manager and synchronizes the Sponsors-specific plan subscription once" do
    org = create(:credit_card_org)
    billing_manager = create(:user, :verified)
    org.billing.add_manager(billing_manager, actor: org.admins.first)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: org, customer: org.customer)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: org,
        actor: billing_manager,
        amounts_by_sponsorable_login: { @sponsorable1.login => "5", @sponsorable2.login => "$10.00" },
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_empty result.errors

    sponsorship1 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable1.id }
    refute_nil sponsorship1
    assert_equal 5_00, sponsorship1.monthly_price_in_cents
    assert_equal org, sponsorship1.sponsor
    assert_equal @sponsorable1, sponsorship1.sponsorable
    refute_predicate sponsorship1, :recurring_payment?
    refute_predicate sponsorship1, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship1, :privacy_public?
    assert_predicate sponsorship1, :active?
    assert_equal plan_sub, sponsorship1.subscription_item.plan_subscription

    sponsorship2 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
    refute_nil sponsorship2
    assert_equal 10_00, sponsorship2.monthly_price_in_cents
    assert_equal org, sponsorship2.sponsor
    assert_equal @sponsorable2, sponsorship2.sponsorable
    refute_predicate sponsorship2, :recurring_payment?
    refute_predicate sponsorship2, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship2, :privacy_public?
    assert_predicate sponsorship2, :active?
    assert_equal plan_sub, sponsorship2.subscription_item.plan_subscription
  end

  test "creates multiple sponsorships from a self-serve enterprise member org and synchronizes once" do
    enterprise = create(:business, :with_self_serve_payment)
    enterprise_owner = enterprise.owners.first
    enterprise.enable_feature(:sponsors_self_serve_enterprise)
    org_admin = create(:user, :verified)
    member_org = create(:organization, business: enterprise, admin: org_admin)
    member_org.grant_sponsorships_access(actor: enterprise_owner)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: nil, customer: enterprise.customer)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: member_org,
        actor: org_admin,
        amounts_by_sponsorable_login: { @sponsorable1.login => "5", @sponsorable2.login => "$10.00" },
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_empty result.errors
  end

  test "handles when sponsor already has an active sponsorship and Sponsors-specific plan subscription" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor)
    sponsorship1 = create(:sponsorship, sponsor: sponsor.reload, sponsorable: @sponsorable1,
      is_sponsor_opted_in_to_email: true)
    original_monthly_price_in_cents = sponsorship1.monthly_price_in_cents
    original_tier = sponsorship1.tier

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      assert_difference(-> { Sponsorship.count }) do # only 1 new Sponsorship
        Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          receive_email: false,
          privacy_level: "private",
        )
      end
    end

    assert_predicate result, :success?
    assert_equal 1, result.sponsorships.size
    assert_equal 1, result.subscription_items.size
    assert_empty result.errors

    assert_equal original_monthly_price_in_cents, sponsorship1.reload.monthly_price_in_cents
    assert_equal sponsor, sponsorship1.sponsor
    assert_equal @sponsorable1, sponsorship1.sponsorable
    assert_predicate sponsorship1, :recurring_payment?
    assert_predicate sponsorship1, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship1, :privacy_public?
    assert_predicate sponsorship1, :active?

    subscription_item1 = result.subscription_items.first
    refute_nil subscription_item1
    assert_equal plan_subscription, subscription_item1.plan_subscription
    tier1 = subscription_item1.subscribable
    refute_nil tier1
    assert_equal 1_00, tier1.monthly_price_in_cents
    assert_equal @sponsorable1, tier1.sponsorable
    assert_predicate tier1, :one_time?
    assert_predicate tier1, :custom?

    sponsorship2 = result.sponsorships.first
    refute_nil sponsorship2
    assert_equal 2_00, sponsorship2.monthly_price_in_cents
    assert_equal sponsor, sponsorship2.sponsor
    assert_equal @sponsorable2, sponsorship2.sponsorable
    refute_predicate sponsorship2, :recurring_payment?
    refute_predicate sponsorship2, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship2, :privacy_private?
    assert_predicate sponsorship2, :active?
  end

  test "stores tier IDs from the bulk sponsorship" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    sponsorable1_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable1_listing,
      monthly_price_in_cents: 1_00)
    sponsorable2_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable2_listing,
      monthly_price_in_cents: 1_00)
    sponsorable1_amount = sponsorable1_tier.monthly_price_in_cents / 100.0
    sponsorable2_amount = sponsorable2_tier.monthly_price_in_cents / 100.0

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: {
          @sponsorable1.login => sponsorable1_amount.to_s,
          @sponsorable2.login => sponsorable2_amount.to_s
        },
        privacy_level: "private",
        receive_email: true,
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_empty result.errors

    expected_tier_ids = [sponsorable1_tier, sponsorable2_tier].map(&:id)
    stored_tier_ids = sponsor.payment_incomplete_bulk_sponsorship_tier_ids

    assert_same_elements expected_tier_ids, stored_tier_ids
  end

  test "does not blow away existing stored tier IDs for the sponsor" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)

    # Store one tier ID for the sponsor, simulating a previous bulk sponsorship that has not finished processing:
    previous_tier = create(:sponsors_tier, :published, :one_time)
    sponsor.save_bulk_sponsorship_tier_ids([previous_tier.id])

    new_tier1 = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable1_listing)
    new_tier2 = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable2_listing)

    result = assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: {
          @sponsorable1.login => new_tier1.monthly_price_in_dollars.to_s,
          @sponsorable2.login => new_tier2.monthly_price_in_dollars.to_s
        },
        privacy_level: "private",
        receive_email: true,
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_empty result.errors
    assert_same_elements [previous_tier, new_tier1, new_tier2].map(&:id),
      sponsor.payment_incomplete_bulk_sponsorship_tier_ids
  end

  test "stores bulk sponsorship tier IDs only for successful sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    sponsorable1_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable1_listing,
      monthly_price_in_cents: 1_00)
    sponsorable1_amount = sponsorable1_tier.monthly_price_in_cents / 100.0

    # Set minimum custom tier amount to 5.00 so adding a 2.00 tier will fail
    @sponsorable2_listing.update!(min_custom_tier_amount_in_cents: 5_00)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"], 1) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => sponsorable1_amount.to_s, @sponsorable2.login => "2.00" },
        privacy_level: "private",
        receive_email: true,
      )
    end

    refute_predicate result, :success?
    assert_equal 1, result.sponsorships.size
    assert_equal 1, result.errors.size

    expected_tier_ids = [sponsorable1_tier.id]
    stored_tier_ids = sponsor.payment_incomplete_bulk_sponsorship_tier_ids

    assert_same_elements expected_tier_ids, stored_tier_ids
  end

  # See more https://github.com/github/sponsors/issues/4616
  test "stores bulk sponsorship tier IDs for concurrent sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable1)
    sponsorable1_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable1_listing,
      monthly_price_in_cents: 1_00)
    sponsorable2_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable2_listing,
      monthly_price_in_cents: 1_00)
    sponsorable1_amount = sponsorable1_tier.monthly_price_in_cents / 100.0
    sponsorable2_amount = sponsorable2_tier.monthly_price_in_cents / 100.0

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference("Billing::SubscriptionItem.count", 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => sponsorable1_amount.to_s, @sponsorable2.login => sponsorable1_amount.to_s },
        privacy_level: "private",
        receive_email: true,
      )
    end

    assert_predicate result, :success?
    assert_equal 1, result.sponsorships.size
    assert_equal 1, result.subscription_items.size

    expected_tier_ids = [sponsorable1_tier, sponsorable2_tier].map(&:id)
    stored_tier_ids = sponsor.payment_incomplete_bulk_sponsorship_tier_ids

    assert_same_elements expected_tier_ids, stored_tier_ids
  end

  test "does not store bulk sponsorship tier IDs unless AddOneTimePayments#call is processed" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never
    Billing::CreateSponsorshipSubscriptionItem.expects(:call).once
      .raises(Billing::CreateSubscriptionItem::UnprocessableError.new("o noes"))

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_equal Set.new, sponsor.payment_incomplete_bulk_sponsorship_tier_ids
  end

  test "returns failure when subscription item fails to create when there is an existing active sponsorship" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)
    sponsorship = create(:sponsorship, sponsor: sponsor.reload, sponsorable: @sponsorable1,
      is_sponsor_opted_in_to_email: true)
    original_monthly_price_in_cents = sponsorship.monthly_price_in_cents
    original_tier = sponsorship.tier

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never
    Billing::CreateSponsorshipSubscriptionItem.expects(:call).once
      .raises(Billing::CreateSubscriptionItem::UnprocessableError.new("o noes"))

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["o noes"], result.errors
  end

  test "returns failure when sponsor is paying via PayPal" do
    sponsor = create(:paypal_customer_account).user
    sponsor.emails.first.verify!

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["GitHub Sponsors no longer accepts PayPal. Update your payment method to be able to sponsor."],
      result.errors
  end

  test "calling methods on result doesn't make excess database queries" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)
    sponsorship1 = create(:sponsorship, sponsor: sponsor.reload, sponsorable: @sponsorable1,
      is_sponsor_opted_in_to_email: true)
    sponsorable3 = create(:user, :sponsorable)
    sponsorship2 = create(:sponsorship, sponsor: sponsor, is_sponsor_opted_in_to_email: true)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["SponsorsTier.count", "Billing::SubscriptionItem.count"], 4) do
      assert_difference(-> { Sponsorship.count }, 2) do
        Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            @sponsorable1.login => "1",
            @sponsorable2.login => "2.00",
            sponsorable3.login => "5",
            sponsorship2.sponsorable.login => "4.00",
          },
        )
      end
    end

    assert_query_count(0) do
      assert_predicate result, :success?
      assert_empty result.errors
      assert_equal 2, result.sponsorships.size
      assert_equal 2, result.subscription_items.size
      assert_equal 4, result.total_sponsored
      assert_equal Billing::Money.new(12_00), result.total_amount_excluding_fees
      assert_predicate result, :any_sponsored_organizations?
      assert_predicate result, :any_sponsored_users?
    end
  end

  test "returns success when no published tier matches" do
    sponsor = create(:credit_card_user, :verified)
    plan_sub = create(:billing_plan_subscription, user: sponsor, purpose: :sponsors, customer: sponsor.customer)
    listing = create(:sponsors_listing, :approved, tier_count: 0, one_time_tier_count: 1)
    sponsorable = listing.sponsorable
    existing_one_time_tier = listing.default_tier
    amount = existing_one_time_tier.monthly_price_in_dollars.to_i + 1

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { sponsorable.login => amount.to_s },
      )
    end

    assert_predicate result, :success?
    assert_equal 1, result.sponsorships.size
    assert_empty result.subscription_items
    assert_empty result.errors

    new_sponsorship = result.sponsorships.first
    assert_equal sponsor, new_sponsorship.sponsor
    assert_equal sponsorable, new_sponsorship.sponsorable
    refute_predicate new_sponsorship, :recurring_payment?
    refute_predicate new_sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate new_sponsorship, :privacy_public?
    assert_predicate new_sponsorship, :active?
    assert_equal plan_sub, new_sponsorship.subscription_item.plan_subscription
    tier = new_sponsorship.tier
    assert_predicate tier, :custom?
    assert_predicate tier, :one_time?
    assert_equal amount * 100, tier.monthly_price_in_cents
    assert_equal sponsor, tier.creator
    assert_equal listing, tier.sponsors_listing
    assert_equal existing_one_time_tier, tier.parent_tier
  end

  test "returns failure when actor lacks a verified email address" do
    sponsor = create(:credit_card_user)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Actor must have a verified email"], result.errors
  end

  test "returns failure when actor specifies another user as sponsor" do
    actor = create(:user, :verified)
    rando = create(:credit_card_user)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: rando,
        actor: actor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Actor does not have permission to sponsor on behalf of #{rando}"],
      result.errors
  end

  test "returns failure when actor specifies an org they only belong to" do
    org_member = create(:user, :verified)
    org = create(:credit_card_org)
    org.add_member(org_member)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: org,
        actor: org_member,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Actor does not have permission to sponsor on behalf of #{org}"],
      result.errors
  end

  test "returns failure when actor specifies an org they have no connection to" do
    rando = create(:user, :verified)
    org = create(:credit_card_org)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: org,
        actor: rando,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Actor does not have permission to sponsor on behalf of #{org}"],
      result.errors
  end

  test "returns failure when no sponsorships are specified" do
    sponsor = create(:credit_card_user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: {},
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Sponsorship amounts and maintainers must be specified"],
      result.errors
  end

  test "returns failure when an amount is not a whole dollar amount" do
    sponsor = create(:credit_card_user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1.50" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Must specify a whole-dollar amount for #{@sponsorable1}"], result.errors
  end

  test "returns failure when sponsor lacks a payment method" do
    sponsor = create(:user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Please add a payment method before checking out."], result.errors
  end

  test "returns failure when no sponsor is specified" do
    sponsor = create(:user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: nil,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Sponsor must be specified"], result.errors
  end

  test "returns failure when no actor is specified" do
    sponsor = create(:credit_card_user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: nil,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Actor must be specified, cannot sponsor anonymously"], result.errors
  end

  test "returns failure when actor is an organization" do
    sponsor = create(:credit_card_user, :verified)
    org = create(:organization, admin: sponsor)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: org,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["Could not create sponsorships: Actor must be a user"], result.errors
  end

  test "returns failure when a specified maintainer is not sponsorable" do
    sponsor = create(:credit_card_user, :verified)
    non_sponsorable = create(:user)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { non_sponsorable.login => "2" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_empty result.subscription_items
    assert_equal ["#{non_sponsorable}: Cannot be sponsored"], result.errors
  end

  test "uses existing published one-time tier when its amount matches" do
    sponsor = create(:credit_card_user, :verified)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)

    # Create a maintainer who has a one-time tier for the amount we want to sponsor at:
    existing_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
    existing_tier_sponsorable = existing_tier.sponsorable

    result = T.let(nil, T.nilable(Sponsors::AddOneTimePayments::Result))
    assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"]) do
      assert_no_difference(-> { SponsorsTier.count }) do
        result = Sponsors::AddOneTimePayments.call(
          sponsor: sponsor.reload,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            # should make a Sponsorship using existing tier:
            existing_tier_sponsorable.login => existing_tier.monthly_price_in_dollars.to_i.to_s,
          },
        )
        assert_empty result.errors
      end
    end

    refute_nil result
    assert_predicate result, :success?
    assert_equal 1, T.must(result).sponsorships.size
    assert_empty T.must(result).subscription_items

    new_sponsorship = T.must(T.must(result).sponsorships.first)
    assert_equal existing_tier, new_sponsorship.tier, "should have used existing published tier of specified price"
    assert_equal sponsor, new_sponsorship.sponsor
    assert_equal existing_tier_sponsorable, new_sponsorship.sponsorable
    refute_predicate new_sponsorship, :recurring_payment?
    refute_predicate new_sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate new_sponsorship, :privacy_public?
    assert_predicate new_sponsorship, :active?
  end

  test "does not stop processing sponsorships when one is invalid" do
    sponsor = create(:credit_card_user, :verified)
    plan_subscription = create(:billing_plan_subscription,
      purpose: :sponsors,
      user: sponsor,
      customer: sponsor.customer,
    )
    non_sponsorable = create(:sponsors_listing, :draft).sponsorable # does not have an approved SponsorsListing
    sponsorable2_sponsorship = create(:sponsorship, sponsor: sponsor.reload, sponsorable: @sponsorable2)
    new_sponsorable2_amount = sponsorable2_sponsorship.tier.monthly_price_in_dollars.to_i + 1

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = T.let(nil, T.nilable(Sponsors::AddOneTimePayments::Result))
    assert_difference(["SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      assert_no_difference(-> { Sponsorship.count }) do
        result = Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            non_sponsorable.login => "5", # should fail

            # has a Sponsorship, should make a SubscriptionItem + tier for custom amount:
            @sponsorable2.login => new_sponsorable2_amount.to_i,
          },
        )

        assert_equal ["#{non_sponsorable}: Cannot be sponsored"], result.errors
      end
    end

    refute_nil result
    refute_predicate result, :success?,
      "one sponsorship should have failed so overall result should not say it was successful"
    assert_empty T.must(result).sponsorships
    assert_equal 1, T.must(result).subscription_items.size,
      "one specified maintainer already has an active Sponsorship so a new SubscriptionItem should have been made"

    subscription_item = T.must(T.must(result).subscription_items.first)
    assert_equal plan_subscription, subscription_item.plan_subscription
    new_tier = subscription_item.subscribable
    assert_instance_of SponsorsTier, new_tier
    assert_equal new_sponsorable2_amount * 100, new_tier.monthly_price_in_cents
    assert_equal @sponsorable2, new_tier.sponsorable
    assert_predicate new_tier, :one_time?
    assert_predicate new_tier, :custom?
  end

  test "instruments sponsorship created for brand new one-time payments via bulk sponsorships" do
    events = subscribe "sponsors.sponsor_sponsorship_create"

    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)

    add_one_time_payments_result = assert_difference("events.size", 2) do
      assert_difference(-> { Sponsorship.count }, 2) do
        Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        )
      end
    end
    sponsorships = add_one_time_payments_result.sponsorships

    assert_equal 2, sponsorships.size
    assert_empty add_one_time_payments_result.subscription_items

    sponsorship1 = sponsorships.first
    sponsorship1_expected_payload = {
      active: true,
      public: true,
      frequency: "one_time",
      current_tier_id: @sponsorable1_listing.sponsors_tiers.last.id,
      current_tier_monthly_amount_in_cents: 100,
      user: sponsor.login,
      user_id: sponsor.id,
      sponsorable_user: @sponsorable1.login,
      sponsorable_user_id: @sponsorable1.id,
      sponsor: sponsor.login,
      sponsor_id: sponsor.id,
      sponsorship_id: sponsorship1.id,
      actor: sponsor.login,
      actor_id: sponsor.id,
      payment_source: "github",
    }
    sponsorship2 = sponsorships.second
    sponsorship2_expected_payload = {
      active: true,
      public: true,
      frequency: "one_time",
      current_tier_id: @sponsorable2_listing.sponsors_tiers.last.id,
      current_tier_monthly_amount_in_cents: 200,
      user: sponsor.login,
      user_id: sponsor.id,
      sponsorable_org: @sponsorable2.login,
      sponsorable_org_id: @sponsorable2.id,
      sponsor: sponsor.login,
      sponsor_id: sponsor.id,
      sponsorship_id: sponsorship2.id,
      actor: sponsor.login,
      actor_id: sponsor.id,
      payment_source: "github",
    }

    assert event = events.pop, "an event was expected"
    assert_equal sponsorship2_expected_payload, event.payload

    assert event = events.pop, "an event was expected"
    assert_equal sponsorship1_expected_payload, event.payload
  end

  test "instruments sponsorship created for reactivated one-time payments via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    initial_sponsorship1 = create(:sponsorship, :one_time, sponsor: sponsor, sponsorable: @sponsorable1)
    initial_sponsorship2 = create(:sponsorship, :one_time, sponsor: sponsor, sponsorable: @sponsorable2)

    initial_sponsorship1.cancel(actor: sponsor, force: true)
    initial_sponsorship2.cancel(actor: sponsor, force: true)

    events = subscribe "sponsors.sponsor_sponsorship_create"

    add_one_time_payments_result = assert_difference("events.size", 2) do
      assert_difference(-> { Sponsorship.active.count }, 2) do
        Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        )
      end
    end
    sponsorships = add_one_time_payments_result.sponsorships

    assert_equal 2, sponsorships.size
    assert_empty add_one_time_payments_result.subscription_items

    sponsorship1 = sponsorships.first
    sponsorship1_expected_payload = {
      active: true,
      public: true,
      frequency: "one_time",
      current_tier_id: @sponsorable1_listing.sponsors_tiers.last.id,
      current_tier_monthly_amount_in_cents: 100,
      user: sponsor.login,
      user_id: sponsor.id,
      sponsorable_user: @sponsorable1.login,
      sponsorable_user_id: @sponsorable1.id,
      sponsor: sponsor.login,
      sponsor_id: sponsor.id,
      sponsorship_id: sponsorship1.id,
      actor: sponsor.login,
      actor_id: sponsor.id,
      payment_source: "github",
    }
    sponsorship2 = sponsorships.second
    sponsorship2_expected_payload = {
      active: true,
      public: true,
      frequency: "one_time",
      current_tier_id: @sponsorable2_listing.sponsors_tiers.last.id,
      current_tier_monthly_amount_in_cents: 200,
      user: sponsor.login,
      user_id: sponsor.id,
      sponsorable_org: @sponsorable2.login,
      sponsorable_org_id: @sponsorable2.id,
      sponsor: sponsor.login,
      sponsor_id: sponsor.id,
      sponsorship_id: sponsorship2.id,
      actor: sponsor.login,
      actor_id: sponsor.id,
      payment_source: "github",
    }

    assert event = events.pop, "an event was expected"
    assert_equal sponsorship2_expected_payload, event.payload

    assert event = events.pop, "an event was expected"
    assert_equal sponsorship1_expected_payload, event.payload
  end

  # The purpose of this test is to record current behavior of how concurrent sponsorships are recorded in Hydro.
  # This behavior will be the case whether the concurrent sponsorship is done via bulk sponsorships or not.
  test "does not instrument sponsorship created for concurrent sponsorships via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable1)
    create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable2)

    events = subscribe "sponsors.sponsor_sponsorship_create"

    add_one_time_payments_result = assert_difference("events.size", 0) do
      assert_difference(-> { Billing::SubscriptionItem.count }, 2) do
        Sponsors::AddOneTimePayments.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        )
      end
    end
    subscription_items = add_one_time_payments_result.subscription_items

    assert_equal 2, subscription_items.size
    assert_empty add_one_time_payments_result.sponsorships

    refute events.pop, "no event was expected"
  end

  test "publishes sponsorship creation to hydro for brand new one-time payments via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)

    add_one_time_payments_result = assert_difference(-> { Sponsorship.count }, 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end
    sponsorships = add_one_time_payments_result.sponsorships

    assert_equal 2, sponsorships.size
    assert_empty add_one_time_payments_result.subscription_items

    sponsorship1 = sponsorships.first.reload
    message1 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable1_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@sponsorable1_listing.sponsors_tiers.last),
      matchable: false,
      action: :CREATE,
      first_time_sponsor: true,
      first_time_sponsorable: true,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @sponsorable1_listing.stafftools_metadata,
      ),
      via_bulk_sponsorship: true,
      payment_source: :GITHUB,
    }
    sponsorship2 = sponsorships.second.reload
    message2 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable2_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@sponsorable2_listing.sponsors_tiers.last),
      matchable: false,
      action: :CREATE,
      first_time_sponsor: false,
      first_time_sponsorable: true,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @sponsorable2_listing.stafftools_metadata,
      ),
      via_bulk_sponsorship: true,
      payment_source: :GITHUB
    }

    assert_hydro_published(message1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_published(message2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
  end

  test "publishes sponsorship creation to hydro for reactivated one-time payments via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    initial_sponsorship1 = create(:sponsorship, :one_time, sponsor: sponsor, sponsorable: @sponsorable1)
    initial_sponsorship2 = create(:sponsorship, :one_time, sponsor: sponsor, sponsorable: @sponsorable2)

    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")

    initial_sponsorship1.cancel(actor: sponsor, force: true)
    initial_sponsorship2.cancel(actor: sponsor, force: true)

    add_one_time_payments_result = assert_difference(-> { Sponsorship.active.count }, 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end
    sponsorships = add_one_time_payments_result.sponsorships

    assert_equal 2, sponsorships.size
    assert_empty add_one_time_payments_result.subscription_items

    sponsorship1 = sponsorships.first.reload
    message1 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable1_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@sponsorable1_listing.sponsors_tiers.last),
      matchable: false,
      action: :CREATE,
      first_time_sponsor: false,
      first_time_sponsorable: false,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @sponsorable1_listing.stafftools_metadata,
      ),
      via_bulk_sponsorship: true,
      payment_source: :GITHUB,
    }
    sponsorship2 = sponsorships.second.reload
    message2 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable2_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@sponsorable2_listing.sponsors_tiers.last),
      matchable: false,
      action: :CREATE,
      first_time_sponsor: false,
      first_time_sponsorable: false,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @sponsorable2_listing.stafftools_metadata,
      ),
      via_bulk_sponsorship: true,
      payment_source: :GITHUB,
    }

    assert_hydro_published(message1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_published(message2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_messages(count: 4, schema: "github.sponsors.v1.SponsorshipCreateCancel")
  end

  # The purpose of this test is to record current behavior of how concurrent sponsorships are recorded in Hydro.
  # This behavior will be the case whether the concurrent sponsorship is done via bulk sponsorships or not.
  test "does not publish sponsorship created to hydro for concurrent sponsorships via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable1)
    create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable2)

    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")

    add_one_time_payments_result = assert_difference(-> { Billing::SubscriptionItem.count }, 2) do
      Sponsors::AddOneTimePayments.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end
    subscription_items = add_one_time_payments_result.subscription_items

    assert_equal 2, subscription_items.size
    assert_empty add_one_time_payments_result.sponsorships

    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
  end
end
