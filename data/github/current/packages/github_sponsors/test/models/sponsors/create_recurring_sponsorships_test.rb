# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::CreateRecurringSponsorshipsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @sponsorable1_listing = create(:sponsors_listing, :approved_with_only_custom_amounts,
      sponsorable_login: "SponsorableTheFirst")
    @sponsorable1 = @sponsorable1_listing.sponsorable
    @sponsorable2_listing = create(:sponsors_listing, :approved_with_only_custom_amounts, :for_org,
      sponsorable_login: "OrgSponsorable")
    @sponsorable2 = @sponsorable2_listing.sponsorable
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    GitHub.flipper[:sponsors_pending_sponsorships].disable
  end

  test "creates multiple sponsorships from a user and synchronizes the Sponsors-specific plan subscription once" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::CreateRecurringSponsorships.call(
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
    assert_predicate sponsorship1, :recurring_payment?
    assert_predicate sponsorship1, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship1, :privacy_private?
    assert_predicate sponsorship1, :active?
    assert_equal plan_sub, sponsorship1.subscription_item.plan_subscription
    assert_equal 1, sponsorship1.subscription_item.quantity

    sponsorship2 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
    refute_nil sponsorship2
    assert_equal 2_00, sponsorship2.monthly_price_in_cents
    assert_equal sponsor, sponsorship2.sponsor
    assert_equal @sponsorable2, sponsorship2.sponsorable
    assert_predicate sponsorship2, :recurring_payment?
    assert_predicate sponsorship2, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship2, :privacy_private?
    assert_predicate sponsorship2, :active?
    assert_equal plan_sub, sponsorship2.subscription_item.plan_subscription
    assert_equal 1, sponsorship2.subscription_item.quantity
  end

  test "creates multiple sponsorships with a specified end date" do
    admin = create(:verified_user)
    sponsor = create(:credit_card_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
      admin: admin)
    plan_sub = sponsor.sponsors_plan_subscription
    end_date = Date.new(2025, 3, 1)

    # ensure there is enough to pay the sponsorships
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(Billing::Money.new(10_00))
    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    travel_to("2024-02-12") do
      result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor.admin,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          privacy_level: "private",
          receive_email: true,
          end_date: end_date,
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
      assert_predicate sponsorship1, :recurring_payment?
      assert_predicate sponsorship1, :is_sponsor_opted_in_to_email?
      assert_predicate sponsorship1, :privacy_private?
      assert_predicate sponsorship1, :active?
      assert_equal plan_sub, sponsorship1.subscription_item.plan_subscription
      assert_equal end_date, sponsorship1.expires_at.to_date

      sponsorship2 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
      refute_nil sponsorship2
      assert_equal 2_00, sponsorship2.monthly_price_in_cents
      assert_equal sponsor, sponsorship2.sponsor
      assert_equal @sponsorable2, sponsorship2.sponsorable
      assert_predicate sponsorship2, :recurring_payment?
      assert_predicate sponsorship2, :is_sponsor_opted_in_to_email?
      assert_predicate sponsorship2, :privacy_private?
      assert_predicate sponsorship2, :active?
      assert_equal plan_sub, sponsorship2.subscription_item.plan_subscription
      assert_equal end_date, sponsorship2.expires_at.to_date
    end
  end

  test "creates multiple sponsorships and skips proration when pay_prorated is false" do
    admin = create(:verified_user)
    sponsor = create(:credit_card_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
      admin: admin)
    plan_sub = sponsor.sponsors_plan_subscription
    sponsor.sponsors_customer.update_columns(bill_cycle_day: 25)

    # ensure there is enough to pay the sponsorships
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(Billing::Money.new(10_00))
    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    travel_to("2023-10-20") do
      result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor.admin,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          receive_email: true,
          pay_prorated: false,
        )
      end

      assert_predicate result, :success?
      assert_equal 2, result.sponsorships.size
      assert_empty result.errors

      [@sponsorable1, 1_00, @sponsorable2, 2_00].each_slice(2) do |sponsorable, amount|
        sponsorship = result.sponsorships.detect { |s| s.sponsorable_id == sponsorable.id }
        refute_nil sponsorship
        assert_equal amount, sponsorship.monthly_price_in_cents
        assert_equal sponsor, sponsorship.sponsor
        assert_equal sponsorable, sponsorship.sponsorable
        assert_predicate sponsorship, :recurring_payment?
        assert_predicate sponsorship, :active?
        assert_equal plan_sub, sponsorship.subscription_item.plan_subscription
        assert_predicate sponsorship, :skip_proration?
      end
    end
  end

  test "creates multiple sponsorships without skipping proration when pay_prorated is true" do
    admin = create(:verified_user)
    sponsor = create(:credit_card_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
      admin: admin)
    plan_sub = sponsor.sponsors_plan_subscription
    sponsor.sponsors_customer.update_columns(bill_cycle_day: 25)

    # ensure there is enough to pay the sponsorships
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(Billing::Money.new(10_00))
    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    travel_to("2023-10-20") do
      result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor.admin,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          receive_email: true,
          pay_prorated: true,
        )
      end

      assert_predicate result, :success?
      assert_equal 2, result.sponsorships.size
      assert_empty result.errors

      [@sponsorable1, 1_00, @sponsorable2, 2_00].each_slice(2) do |sponsorable, amount|
        sponsorship = result.sponsorships.detect { |s| s.sponsorable_id == sponsorable.id }
        refute_nil sponsorship
        assert_equal amount, sponsorship.monthly_price_in_cents
        assert_equal sponsor, sponsorship.sponsor
        assert_equal sponsorable, sponsorship.sponsorable
        assert_predicate sponsorship, :recurring_payment?
        assert_predicate sponsorship, :active?
        assert_equal plan_sub, sponsorship.subscription_item.plan_subscription
        refute_predicate sponsorship, :skip_proration?
      end
    end
  end

  test "calls the given after-payment lambda" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    successful_logins = []

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::CreateRecurringSponsorships.call(
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
      Sponsors::CreateRecurringSponsorships.call(
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
    assert_predicate sponsorship1, :recurring_payment?
    refute_predicate sponsorship1, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship1, :privacy_public?
    assert_predicate sponsorship1, :active?
    assert_equal plan_sub, sponsorship1.subscription_item.plan_subscription

    sponsorship2 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
    refute_nil sponsorship2
    assert_equal 10_00, sponsorship2.monthly_price_in_cents
    assert_equal org, sponsorship2.sponsor
    assert_equal @sponsorable2, sponsorship2.sponsorable
    assert_predicate sponsorship2, :recurring_payment?
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
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: member_org,
        actor: org_admin,
        amounts_by_sponsorable_login: { @sponsorable1.login => "5", @sponsorable2.login => "$10.00" },
      )
    end

    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_empty result.errors
  end

  test "does not modify existing active recurring sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor)
    sponsorship1 = create(:sponsorship, sponsor: sponsor.reload, sponsorable: @sponsorable1,
      is_sponsor_opted_in_to_email: true)
    original_tier1 = sponsorship1.tier
    sponsorship2 = create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable2,
      is_sponsor_opted_in_to_email: true)
    original_tier2 = sponsorship2.tier

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: {
          @sponsorable1.login => (original_tier1.monthly_price_in_dollars + 1).to_s,
          @sponsorable2.login => (original_tier2.monthly_price_in_dollars + 1).to_s
        },
        receive_email: false,
        privacy_level: "private",
      )
    end

    refute_predicate result, :success?
    assert_same_elements [
      "#{@sponsorable1}: You are already sponsoring this maintainer",
      "#{@sponsorable2}: You are already sponsoring this maintainer",
    ], result.errors
    assert_predicate sponsorship1.reload, :is_sponsor_opted_in_to_email?,
      "should not have updated existing sponsorship1's email setting"
    assert_predicate sponsorship2.reload, :is_sponsor_opted_in_to_email?,
      "should not have updated existing sponsorship2's email setting"
    assert_equal original_tier1, sponsorship1.tier, "should not have changed sponsorship1's tier"
    assert_equal original_tier2, sponsorship2.tier, "should not have changed sponsorship2's tier"
  end

  test "stores tier IDs from the bulk sponsorship" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    sponsorable1_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsorable1_listing,
      monthly_price_in_cents: 1_00)
    sponsorable2_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsorable2_listing,
      monthly_price_in_cents: 1_00)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"], 2) do
      assert_no_difference("SponsorsTier.count") do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            @sponsorable1.login => sponsorable1_tier.monthly_price_in_dollars.to_i.to_s,
            @sponsorable2.login => sponsorable2_tier.monthly_price_in_dollars.to_i,
          },
          privacy_level: "private",
          receive_email: true,
        )
      end
    end

    assert_empty result.errors
    assert_predicate result, :success?
    assert_equal 2, result.sponsorships.size
    assert_same_elements [sponsorable1_tier, sponsorable2_tier].map(&:id),
      sponsor.payment_incomplete_bulk_sponsorship_tier_ids
  end

  test "does not blow away existing stored tier IDs for the sponsor" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)

    # Store one tier ID for the sponsor, simulating a previous bulk sponsorship that has not finished processing:
    previous_tier = create(:sponsors_tier, :published, :one_time) # could have been a one-time bulk sponsorship
    sponsor.save_bulk_sponsorship_tier_ids([previous_tier.id])

    new_tier1 = create(:sponsors_tier, :published, sponsors_listing: @sponsorable1_listing)
    new_tier2 = create(:sponsors_tier, :published, sponsors_listing: @sponsorable2_listing)

    result = assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::CreateRecurringSponsorships.call(
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
    sponsorable1_tier = create(:sponsors_tier, :published, sponsors_listing: @sponsorable1_listing,
      monthly_price_in_cents: 1_00)
    sponsorable1_amount = sponsorable1_tier.monthly_price_in_cents / 100.0

    # Set minimum custom tier amount to 5.00 so adding a 2.00 tier will fail
    @sponsorable2_listing.update!(min_custom_tier_amount_in_cents: 5_00)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"], 1) do
      Sponsors::CreateRecurringSponsorships.call(
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
    assert_same_elements [sponsorable1_tier.id], sponsor.payment_incomplete_bulk_sponsorship_tier_ids
  end

  test "does not store bulk sponsorship tier IDs unless CreateRecurringSponsorships#call is processed" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never
    Billing::CreateSponsorshipSubscriptionItem.expects(:call).once
      .raises(Billing::CreateSubscriptionItem::UnprocessableError.new("o noes"))

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_equal Set.new, sponsor.payment_incomplete_bulk_sponsorship_tier_ids
  end

  test "returns failure when sponsor is paying via PayPal" do
    sponsor = create(:paypal_customer_account).user
    sponsor.emails.first.verify!

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["GitHub Sponsors no longer accepts PayPal. Update your payment method to be able to sponsor."],
      result.errors
  end

  test "calling methods on result doesn't make excess database queries" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)
    sponsorship1 = create(:sponsorship, :one_time, :unlocked, sponsor: sponsor.reload, sponsorable: @sponsorable1)
    sponsorship1_old_sub_item = sponsorship1.subscription_item
    sponsorable3 = create(:sponsors_listing, :approved_with_only_custom_amounts).sponsorable
    inactive_sponsorship = create(:sponsorship, :inactive, sponsor: sponsor)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(-> { SponsorsTier.count }, 3) do # will reuse inactive sponsorship's tier
      assert_difference(-> { Sponsorship.count }, 2) do # 2 out of 4 Sponsorship records already exist
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            @sponsorable1.login => "10",
            @sponsorable2.login => "12",
            sponsorable3.login => "14",
            inactive_sponsorship.sponsorable.login => inactive_sponsorship.tier.monthly_price_in_dollars.to_s,
          },
        )
      end
    end

    assert_query_count(0) do
      assert_predicate result, :success?
      assert_empty result.errors
      assert_equal 4, result.sponsorships.size
      assert_equal 4, result.total_sponsored
      assert_equal inactive_sponsorship.amount + Billing::Money.new(36_00), result.total_amount_excluding_fees
      assert_predicate result, :any_sponsored_organizations?
      assert_predicate result, :any_sponsored_users?
    end

    assert_predicate sponsorship1.reload, :recurring_payment?,
      "should have updated existing sponsorship to be the recurring one"
    refute_equal sponsorship1_old_sub_item, sponsorship1.subscription_item,
      "should have moved the one-time subscription item off the sponsorship"
    assert_predicate inactive_sponsorship.reload, :active?, "should have reactivated inactive sponsorship"
  end

  test "returns success when no published tier matches" do
    sponsor = create(:credit_card_user, :verified)
    plan_sub = create(:billing_plan_subscription, user: sponsor, purpose: :sponsors, customer: sponsor.customer)
    listing = create(:sponsors_listing, :approved, tier_count: 1)
    sponsorable = listing.sponsorable
    existing_tier = listing.default_tier
    amount = existing_tier.monthly_price_in_dollars.to_i + 1

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { sponsorable.login => amount.to_s },
      )
    end

    assert_predicate result, :success?
    assert_equal 1, result.sponsorships.size
    assert_empty result.errors

    new_sponsorship = result.sponsorships.first
    assert_equal sponsor, new_sponsorship.sponsor
    assert_equal sponsorable, new_sponsorship.sponsorable
    assert_predicate new_sponsorship, :recurring_payment?
    refute_predicate new_sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate new_sponsorship, :privacy_public?
    assert_predicate new_sponsorship, :active?
    assert_equal plan_sub, new_sponsorship.subscription_item.plan_subscription
    tier = new_sponsorship.tier
    assert_predicate tier, :custom?
    refute_predicate tier, :one_time?
    assert_equal amount * 100, tier.monthly_price_in_cents
    assert_equal sponsor, tier.creator
    assert_equal listing, tier.sponsors_listing
    assert_equal existing_tier, tier.parent_tier
  end

  test "returns failure when actor lacks a verified email address" do
    sponsor = create(:credit_card_user)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Actor must have a verified email"], result.errors
  end

  test "returns failure when actor specifies another user as sponsor" do
    actor = create(:user, :verified)
    rando = create(:credit_card_user)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: rando,
        actor: actor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Actor does not have permission to sponsor on behalf of #{rando}"],
      result.errors
  end

  test "returns failure when actor specifies an org they only belong to" do
    org_member = create(:user, :verified)
    org = create(:credit_card_org)
    org.add_member(org_member)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: org,
        actor: org_member,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Actor does not have permission to sponsor on behalf of #{org}"],
      result.errors
  end

  test "returns failure when actor specifies an org they have no connection to" do
    rando = create(:user, :verified)
    org = create(:credit_card_org)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: org,
        actor: rando,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Actor does not have permission to sponsor on behalf of #{org}"],
      result.errors
  end

  test "returns failure when no sponsorships are specified" do
    sponsor = create(:credit_card_user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: {},
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Sponsorship amounts and maintainers must be specified"],
      result.errors
  end

  test "returns failure when an amount is not a whole dollar amount" do
    sponsor = create(:credit_card_user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1.50" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Must specify a whole-dollar amount for #{@sponsorable1}"], result.errors
  end

  test "returns failure when sponsor lacks a payment method" do
    sponsor = create(:user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Please add a payment method before checking out."], result.errors
  end

  test "returns failure when no sponsor is specified" do
    sponsor = create(:user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: nil,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Sponsor must be specified"], result.errors
  end

  test "returns failure when no actor is specified" do
    sponsor = create(:credit_card_user, :verified)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: nil,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Actor must be specified, cannot sponsor anonymously"], result.errors
  end

  test "returns failure when actor is an organization" do
    sponsor = create(:credit_card_user, :verified)
    org = create(:organization, admin: sponsor)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: org,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["Could not create sponsorships: Actor must be a user"], result.errors
  end

  test "returns failure when a specified maintainer is not sponsorable" do
    sponsor = create(:credit_card_user, :verified)
    non_sponsorable = create(:user)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

    result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { non_sponsorable.login => "2" },
      )
    end

    refute_predicate result, :success?
    assert_empty result.sponsorships
    assert_equal ["#{non_sponsorable}: Cannot be sponsored"], result.errors
  end

  test "uses existing published recurring tier when its amount matches" do
    sponsor = create(:credit_card_user, :verified)
    plan_subscription = create(:billing_plan_subscription, user: sponsor)

    existing_tier = create(:sponsors_tier, :approved_sponsors_listing)
    existing_tier_sponsorable = existing_tier.sponsorable

    result = T.let(nil, T.nilable(Sponsors::CreateRecurringSponsorships::Result))
    assert_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"]) do
      assert_no_difference(-> { SponsorsTier.count }) do
        result = Sponsors::CreateRecurringSponsorships.call(
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

    new_sponsorship = T.must(T.must(result).sponsorships.first)
    assert_equal existing_tier, new_sponsorship.tier, "should have used existing published tier of specified price"
    assert_equal sponsor, new_sponsorship.sponsor
    assert_equal existing_tier_sponsorable, new_sponsorship.sponsorable
    assert_predicate new_sponsorship, :recurring_payment?
    refute_predicate new_sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate new_sponsorship, :privacy_public?
    assert_predicate new_sponsorship, :active?
  end

  test "does not stop processing sponsorships when one is invalid" do
    sponsor = create(:credit_card_user, :verified)
    plan_subscription = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor,
      customer: sponsor.customer)
    non_sponsorable = create(:sponsors_listing, :draft).sponsorable # does not have an approved SponsorsListing

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = T.let(nil, T.nilable(Sponsors::CreateRecurringSponsorships::Result))
    assert_difference(["SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
      assert_difference(-> { Sponsorship.count }) do # only 1 sponsorship should be made, one of them will error
        result = Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            non_sponsorable.login => "5", # should fail
            @sponsorable2.login => 5,
          },
        )

        assert_equal ["#{non_sponsorable}: Cannot be sponsored"], result.errors
      end
    end

    refute_nil result
    refute_predicate result, :success?,
      "one sponsorship should have failed so overall result should not say it was successful"
    assert_equal 1, T.must(result).sponsorships.size

    new_sponsorship = T.must(T.must(result).sponsorships.first)
    assert_equal sponsor, new_sponsorship.sponsor
    assert_equal @sponsorable2, new_sponsorship.sponsorable
    assert_predicate new_sponsorship, :recurring_payment?
    refute_predicate new_sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate new_sponsorship, :privacy_public?
    assert_predicate new_sponsorship, :active?
  end

  test "errors if end date is specified and sponsor is not an organization" do
    sponsor = create(:credit_card_user, :verified)
    plan_subscription = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor,
      customer: sponsor.customer)
    end_date = Date.new(2025, 3, 1)

    # ensure there is enough to pay the sponsorships
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(Billing::Money.new(10_00))

    travel_to("2024-02-12") do
      result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          privacy_level: "private",
          receive_email: true,
          end_date: end_date,
        )
      end

      refute_predicate result, :success?
      assert_equal 0, result.sponsorships.size
      assert_equal ["You cannot set an end date for these sponsorships."], result.errors
    end
  end

  test "errors if end date is specified and org sponsor is not invoiced" do
    admin = create(:verified_user)
    sponsor = create(:credit_card_org, admin: admin)
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)
    end_date = Date.new(2025, 3, 1)

    # ensure there is enough to pay the sponsorships
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(Billing::Money.new(10_00))

    travel_to("2024-02-12") do
      result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: admin,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          privacy_level: "private",
          receive_email: true,
          end_date: end_date,
        )
      end

      refute_predicate result, :success?
      assert_equal 0, result.sponsorships.size
      assert_equal ["You cannot set an end date for these sponsorships."], result.errors
    end
  end

  test "errors if end date is in the past for an invoiced organization" do
    admin = create(:verified_user)
    sponsor = create(:credit_card_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
      admin: admin)
    plan_sub = sponsor.sponsors_plan_subscription
    end_date = Date.new(2024, 1, 1)

    # ensure there is enough to pay the sponsorships
    ::Billing::Zuora::Account.any_instance.stubs(:credit_balance).returns(Billing::Money.new(10_00))

    travel_to("2024-02-12") do
      result = assert_no_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"]) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor.admin,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
          privacy_level: "private",
          receive_email: true,
          end_date: end_date,
        )
      end

      refute_predicate result, :success?
      assert_equal 0, result.sponsorships.size
      assert_equal ["Please choose an end date in the future."], result.errors
    end
  end

  test "instruments sponsorship created for brand new recurring sponsorships via bulk sponsorships" do
    events = subscribe "sponsors.sponsor_sponsorship_create"

    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)

    result = assert_difference("events.size", 2) do
      assert_difference(-> { Sponsorship.count }, 2) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        )
      end
    end

    sponsorships = result.sponsorships
    assert_equal 2, sponsorships.size

    sponsorship1 = sponsorships.first
    sponsorship1_expected_payload = {
      active: true,
      public: true,
      frequency: "recurring",
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
      frequency: "recurring",
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

    refute_nil event = events.pop, "an event was expected"
    assert_equal sponsorship2_expected_payload, event.payload

    refute_nil event = events.pop, "an event was expected"
    assert_equal sponsorship1_expected_payload, event.payload
  end

  test "instruments sponsorship created for reactivated recurring sponsorships via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    initial_sponsorship1 = create(:sponsorship, :inactive, sponsor: sponsor, sponsorable: @sponsorable1)
    initial_sponsorship2 = create(:sponsorship, :inactive, sponsor: sponsor, sponsorable: @sponsorable2)

    events = subscribe("sponsors.sponsor_sponsorship_create")

    result = assert_difference("events.size", 2) do
      assert_difference(-> { Sponsorship.active.count }, 2) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        )
      end
    end

    sponsorships = result.sponsorships
    assert_equal 2, sponsorships.size

    sponsorship1 = sponsorships.first
    sponsorship1_expected_payload = {
      active: true,
      public: true,
      frequency: "recurring",
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
      frequency: "recurring",
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

    refute_nil event = events.pop, "an event was expected"
    assert_equal sponsorship2_expected_payload, event.payload

    refute_nil event = events.pop, "an event was expected"
    assert_equal sponsorship1_expected_payload, event.payload
  end

  test "publishes sponsorship creation to Hydro for brand new recurring sponsorships via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)

    result = assert_difference(-> { Sponsorship.count }, 2) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
      )
    end

    assert_equal 2, result.sponsorships.size
    sponsorship1 = result.sponsorships.first.reload
    assert_predicate sponsorship1.tier, :recurring?
    assert_equal 1_00, sponsorship1.tier.monthly_price_in_cents
    message1 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable1_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(sponsorship1.tier),
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
    sponsorship2 = result.sponsorships.second.reload
    assert_predicate sponsorship2.tier, :recurring?
    assert_equal 2_00, sponsorship2.tier.monthly_price_in_cents
    message2 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable2_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(sponsorship2.tier),
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

  test "publishes sponsorship creation to Hydro for reactivated recurring sponsorships via bulk sponsorships" do
    sponsor = create(:credit_card_user, :verified, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    initial_sponsorship1 = create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable1)
    initial_sponsorship2 = create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable2)

    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")

    initial_sponsorship1.cancel(actor: sponsor, force: true)
    initial_sponsorship2.cancel(actor: sponsor, force: true)

    new_dollar_amount1 = initial_sponsorship1.monthly_price_in_dollars.to_i + 1
    new_dollar_amount2 = initial_sponsorship2.monthly_price_in_dollars.to_i + 1

    result = assert_no_difference(-> { Sponsorship.count }) do
      assert_difference(-> { SponsorsTier.with_custom_state.recurring.count }, 2) do
        Sponsors::CreateRecurringSponsorships.call(
          sponsor: sponsor,
          actor: sponsor,
          amounts_by_sponsorable_login: {
            @sponsorable1.login => new_dollar_amount1.to_s,
            @sponsorable2.login => new_dollar_amount2.to_s,
          },
        )
      end
    end

    assert_equal 2, result.sponsorships.size
    assert_same_elements [initial_sponsorship1.id, initial_sponsorship2.id], result.sponsorships.map(&:id),
      "should have updated existing sponsorships rather than creating new ones"
    sponsorship1 = result.sponsorships.first.reload
    assert_equal @sponsorable1_listing.sponsors_tiers.with_custom_state.recurring.last, sponsorship1.tier
    assert_equal new_dollar_amount1, sponsorship1.monthly_price_in_dollars.to_i
    message1 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship1),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable1_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(sponsorship1.tier),
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
    sponsorship2 = result.sponsorships.second.reload
    assert_equal @sponsorable2_listing.sponsors_tiers.with_custom_state.recurring.last, sponsorship2.tier
    assert_equal new_dollar_amount2, sponsorship2.monthly_price_in_dollars.to_i
    message2 = {
      actor: Hydro::EntitySerializer.user(sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship2),
      listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable2_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(sponsorship2.tier),
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
  end

  test "creates multiple sponsorships with pending sub item changes when active_on is passed in" do
    sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)

    bill_on = sponsor.next_sponsors_billing_date + 10.days
    sponsor.update(billed_on: bill_on)

    plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor, customer: sponsor.customer)

    Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

    result = assert_difference(["Sponsorship.count", "SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
      Sponsors::CreateRecurringSponsorships.call(
        sponsor: sponsor,
        actor: sponsor,
        amounts_by_sponsorable_login: { @sponsorable1.login => "1", @sponsorable2.login => "2.00" },
        privacy_level: "private",
        receive_email: true,
        active_on: bill_on
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
    assert_predicate sponsorship1, :recurring_payment?
    assert_predicate sponsorship1, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship1, :privacy_private?
    assert_predicate sponsorship1, :active?

    sub_item1 = sponsorship1.subscription_item
    assert_equal plan_sub, sub_item1.plan_subscription
    assert_equal 0, sub_item1.quantity

    pending_change = sub_item1.pending_subscription_item_change
    refute_nil pending_change
    assert_equal 1, pending_change.quantity
    assert_equal sponsorship1.tier, pending_change.subscribable
    assert_equal bill_on, pending_change.active_on

    sponsorship2 = result.sponsorships.detect { |s| s.sponsorable_id == @sponsorable2.id }
    refute_nil sponsorship2
    assert_equal 2_00, sponsorship2.monthly_price_in_cents
    assert_equal sponsor, sponsorship2.sponsor
    assert_equal @sponsorable2, sponsorship2.sponsorable
    assert_predicate sponsorship2, :recurring_payment?
    assert_predicate sponsorship2, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship2, :privacy_private?
    assert_predicate sponsorship2, :active?

    sub_item2 = sponsorship2.subscription_item
    assert_equal plan_sub, sub_item2.plan_subscription
    assert_equal 0, sub_item2.quantity

    pending_change = sub_item2.pending_subscription_item_change
    refute_nil pending_change
    assert_equal 1, pending_change.quantity
    assert_equal sponsorship2.tier, pending_change.subscribable
    assert_equal bill_on, pending_change.active_on
  end
end
