# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsUpdateSponsorshipTierTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::ZuoraTestHelper

  fixtures do
    @listing = create(:sponsors_listing, :approved, tier_count: 3)
    @sponsorable = @listing.sponsorable
    @downgrade_tier, @tier, @upgrade_tier = @listing.sponsors_tiers.order(:monthly_price_in_cents)
    @one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @listing,
      monthly_price_in_cents: @tier.monthly_price_in_cents)
    @sponsor = create :credit_card_user, :with_valid_contact_for_billing, :verified, plan_subscription: create(:billing_plan_subscription)
    @sponsorship = create(:sponsorship, sponsor: @sponsor, sponsorable: @sponsorable, tier: @tier)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  if GitHub.spamminess_check_enabled?
    test "disallows tier change from a spammy user" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { @sponsor.mark_as_spammy }

      error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
        Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier)
      end

      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end

    test "disallows tier change from a spammy organization" do
      sponsorship = create(:sponsorship, :from_org, tier: @tier)
      org_sponsor = sponsorship.sponsor
      org_admin = org_sponsor.admins.first
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { org_sponsor.mark_as_spammy }
      sponsor_item = sponsorship.subscription_item
      assert_predicate sponsor_item.plan_subscription.reload_user, :spammy?

      error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
        Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: org_admin, new_tier: @downgrade_tier)
      end

      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end
  end

  test "points Sponsorship at new tier immediately for upgrades" do
    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier)
    assert_equal @upgrade_tier, @sponsorship.reload.tier
    assert_equal @upgrade_tier, @sponsorship.reload_subscription_item.subscribable
  end

  test "changes tier for a Patreon sponsorship" do
    sponsorable_patreon_user = create(:sponsors_patreon_user, user: @sponsorable)
    old_patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: sponsorable_patreon_user,
      amount_in_cents: 5_00)
    new_patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: sponsorable_patreon_user,
      amount_in_cents: 10_00)
    sponsor_patreon_user = create(:sponsors_patreon_user, :sponsor)
    patreon_sponsor = sponsor_patreon_user.user
    old_tier = create(:sponsors_tier, :custom, creator: patreon_sponsor,
      monthly_price_in_cents: old_patreon_tier.amount_in_cents, sponsors_listing: @listing)
    new_tier = create(:sponsors_tier, :custom, creator: patreon_sponsor,
      monthly_price_in_cents: new_patreon_tier.amount_in_cents, sponsors_listing: @listing)
    patreon_sponsorship = create(:sponsorship, :patreon, sponsor: patreon_sponsor, sponsorable: @sponsorable,
      tier: old_tier)
    audit_log_events = subscribe("sponsors.sponsor_sponsorship_tier_change")

    Sponsors::UpdateSponsorshipTier.call(patreon_sponsorship, viewer: patreon_sponsor, new_tier: new_tier)

    assert_equal new_tier, patreon_sponsorship.reload.tier
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTierChange")
    assert_hydro_published({
      actor: Hydro::EntitySerializer.user(patreon_sponsor),
      sponsorship: Hydro::EntitySerializer.sponsorship(patreon_sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      previous_tier: Hydro::EntitySerializer.sponsors_tier(old_tier),
      current_tier: Hydro::EntitySerializer.sponsors_tier(new_tier),
    }, schema: "github.sponsors.v1.SponsorshipTierChange")

    expected_payload = {
      sponsorship_id: patreon_sponsorship.id,
      sponsor: patreon_sponsor.login,
      sponsor_id: patreon_sponsor.id,
      actor: patreon_sponsor.login,
      actor_id: patreon_sponsor.id,
      user: patreon_sponsor.login,
      user_id: patreon_sponsor.id,
      frequency: "recurring",
      previous_tier_id: old_tier.id,
      current_tier_id: new_tier.id,
      current_tier_monthly_amount_in_cents: new_tier.monthly_price_in_cents,
      sponsorable_user: @listing.sponsorable_login,
      sponsorable_user_id: @listing.sponsorable_id,
      public: true,
      active: true,
      payment_source: "patreon",
    }
    refute_nil event = audit_log_events.pop, "should have had an audit log event"
    assert_equal expected_payload, event.payload
  end

  test "updates Zuora-based invoiced sponsorship on Sponsors-specific plan subscription when changing tier" do
    stub_credit_balance do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @sponsorable, tier: @tier)
      old_sponsor_item = sponsorship.subscription_item
      plan_sub = old_sponsor_item.plan_subscription
      assert_predicate plan_sub, :sponsors_purpose?
      invoiced_org_admin = invoiced_org.admins.first

      assert_difference(-> { Billing::SubscriptionItem.count }) do
        Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: invoiced_org_admin, new_tier: @upgrade_tier)
      end

      new_sponsor_item = sponsorship.reload.subscription_item
      refute_equal new_sponsor_item, old_sponsor_item
      refute_nil new_sponsor_item
      assert_equal plan_sub, new_sponsor_item.reload.plan_subscription,
        "should have kept the same Sponsors-specific plan subscription"
      assert_equal @upgrade_tier, sponsorship.reload.tier, "should have updated the sponsorship's tier"
      assert_equal @upgrade_tier, new_sponsor_item.subscribable,
        "should have used the new tier for the new subscription item's subscribable"
    end
  end

  test "sponsorship remains active for upgrades" do
    old_activated_at = @sponsorship.activated_at

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier)

    assert_predicate @sponsorship.reload, :active?
    assert_equal old_activated_at, @sponsorship.activated_at,
      "activation time should not have changed for tier change"
  end

  test "bumps expires_at and subscribable_selected_at when changing one-time tiers" do
    travel_to "2023-11-05 08:58:37"
    diff_in_days = Sponsorship::LOCK_CUTOFF_IN_DAYS + 1
    sponsorship = travel_to(diff_in_days.days.ago) do
      create(:sponsorship, :one_time, sponsorable: @sponsorable, tier: @one_time_tier)
    end
    sponsor = sponsorship.sponsor
    old_expiration = sponsorship.expires_at
    old_tier_selection_time = sponsorship.subscribable_selected_at
    refute_nil old_expiration
    old_activated_at = sponsorship.activated_at
    refute_nil old_tier_selection_time

    freeze_time do
      new_tier = create(:sponsors_tier, :one_time, :published, sponsors_listing: @listing)

      Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: new_tier, viewer: sponsor)

      assert_predicate sponsorship.reload, :active?
      refute_nil sponsorship.subscribable_selected_at, "should have set subscribable_selected_at"
      assert_operator old_tier_selection_time, :<, sponsorship.subscribable_selected_at,
        "should have moved subscribable_selected_at ahead"
      assert_equal diff_in_days,
        (sponsorship.subscribable_selected_at.to_date - old_tier_selection_time.to_date).to_i,
        "expected subscribable_selected_at time to move forward #{diff_in_days} days"
      assert_equal new_tier, sponsorship.tier
      assert_equal sponsor, sponsorship.sponsor
      assert_equal @sponsorable, sponsorship.sponsorable
      new_expiration = sponsorship.expires_at
      refute_nil new_expiration
      refute_equal old_expiration, new_expiration
      assert_equal Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.from_now.end_of_day.to_s,
        new_expiration.to_s
      assert_equal old_activated_at, sponsorship.activated_at
      refute_nil sponsorship.subscribable_selected_at
      refute_equal old_tier_selection_time, sponsorship.subscribable_selected_at
    end
  end

  test "Sponsorship stays pointed at old tier for scheduled downgrades" do
    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @downgrade_tier)
    assert_equal @tier, @sponsorship.reload_subscription_item.subscribable
  end

  test "Sponsorship remains active for downgrades" do
    old_activated_at = @sponsorship.activated_at

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @downgrade_tier)

    assert_predicate @sponsorship.reload, :active?
    assert_equal old_activated_at, @sponsorship.activated_at
  end

  test "updates latest sponsorable metadata" do
    old_sponsorble_metadata = { "metadata_source" => "hacktoberfest 2020" }
    sponsorable_metadata = { "metadata_source" => "hacktoberfest" }
    latest_sponsorable_metadata = { "source" => "hacktoberfest" }

    sponsorship = create(:sponsorship, privacy_level: "public", tier: @tier, is_sponsor_opted_in_to_email: false, latest_sponsorable_metadata: old_sponsorble_metadata)

    Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: sponsorship.sponsor, new_tier: @upgrade_tier, sponsorable_metadata: sponsorable_metadata)

    assert_equal latest_sponsorable_metadata, sponsorship.reload.latest_sponsorable_metadata
  end

  test "updates latest sponsorable metadata when empty" do
    old_sponsorble_metadata = { "metadata_source" => "hacktoberfest 2020" }
    sponsorable_metadata = {}

    sponsorship = create(:sponsorship, privacy_level: "public", tier: @tier, is_sponsor_opted_in_to_email: false, latest_sponsorable_metadata: old_sponsorble_metadata)

    Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: sponsorship.sponsor, new_tier: @upgrade_tier, sponsorable_metadata: sponsorable_metadata)

    assert_nil sponsorship.reload.latest_sponsorable_metadata
  end

  test "updates latest sponsorable metadata when nil" do
    old_sponsorble_metadata = { "metadata_source" => "hacktoberfest 2020" }
    sponsorable_metadata = nil

    sponsorship = create(:sponsorship, privacy_level: "public", tier: @tier, is_sponsor_opted_in_to_email: false, latest_sponsorable_metadata: old_sponsorble_metadata)

    Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: sponsorship.sponsor, new_tier: @upgrade_tier, sponsorable_metadata: sponsorable_metadata)

    assert_nil sponsorship.reload.latest_sponsorable_metadata
  end

  test "raises on tier change if sponsorship is locked" do
    travel_to "2023-11-13"
    locked_sponsorship = travel_to(1.hour.ago) do
      create(:sponsorship, sponsorable: @sponsorable, tier: @one_time_tier)
    end
    other_tier = create :sponsors_tier, :published, listing: @listing,
      monthly_price_in_cents: @one_time_tier.monthly_price_in_cents * 2,
      yearly_price_in_cents: @one_time_tier.yearly_price_in_cents * 2
    old_subscribable_selected_at = locked_sponsorship.subscribable_selected_at

    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(locked_sponsorship, new_tier: other_tier,
        viewer: locked_sponsorship.sponsor)
    end

    assert_equal "Could not update sponsorship while it is processing", error.message
    assert_equal @one_time_tier, locked_sponsorship.reload.tier
    assert_predicate locked_sponsorship, :locked?
    assert_equal old_subscribable_selected_at, locked_sponsorship.subscribable_selected_at
  end

  test "disallows changing tiers for sponsorships with pending cancellations" do
    sponsorship = create(:sponsorship)
    tier = sponsorship.tier
    sponsor = sponsorship.sponsor
    sponsorable = sponsorship.sponsorable
    change = create(:billing_pending_plan_change, user: sponsor)
    create(:sponsors_pending_subscription_item_change, pending_plan_change: change, subscribable: tier, quantity: 0)
    new_tier = create(:sponsors_tier, :published, listing: sponsorable.sponsors_listing)

    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: new_tier, viewer: sponsor)
    end

    assert_match /this sponsorship is pending cancellation/, error.message
    assert_equal tier, sponsorship.reload.tier
  end

  test "disallows changing tiers for sponsorships with pending downgrade" do
    sponsorship = create(:sponsorship)
    tier = sponsorship.tier
    sponsor = sponsorship.sponsor
    sponsorable = sponsorship.sponsorable
    change = create(:billing_pending_plan_change, user: sponsor)
    create(:sponsors_pending_subscription_item_change, pending_plan_change: change, subscribable: tier, quantity: 1)
    new_tier = create(:sponsors_tier, :published, listing: sponsorable.sponsors_listing)

    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: new_tier, viewer: sponsor)
    end

    assert_match /this sponsorship has a pending tier change/, error.message
    assert_equal tier, sponsorship.reload.tier
  end

  test "raises on tier change when payment method is PayPal" do
    travel_to "2023-11-13"
    customer_account = create(:paypal_customer_account)
    sponsor = customer_account.user
    create(:billing_plan_subscription, user: sponsor, customer: customer_account.customer)
    sponsor.emails.first.verify!
    sponsorship = create(:sponsorship, :unlocked, sponsor: sponsor, sponsorable: @sponsorable, tier: @one_time_tier)
    new_tier = create :sponsors_tier, :published, :one_time, listing: @listing,
      monthly_price_in_cents: @one_time_tier.monthly_price_in_cents * 2,
      yearly_price_in_cents: @one_time_tier.yearly_price_in_cents * 2
    old_subscribable_selected_at = sponsorship.subscribable_selected_at

    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: new_tier, viewer: sponsor)
    end

    assert_equal "GitHub Sponsors no longer accepts PayPal. Update your payment method to continue sponsoring.",
      error.message
    assert_equal @one_time_tier, sponsorship.reload.tier
    assert_equal old_subscribable_selected_at, sponsorship.subscribable_selected_at
  end

  test "disallows changing from a recurring to a one-time tier" do
    sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: @downgrade_tier)

    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: @one_time_tier, viewer: sponsorship.sponsor)
    end

    assert_equal "Cannot switch from monthly to one-time", error.message
    assert_equal @downgrade_tier, sponsorship.reload.tier
    assert_nil sponsorship.expires_at
    refute_predicate sponsorship, :locked?
  end

  test "disallows changing from a one-time to a recurring tier" do
    sponsorship = create(:sponsorship, :unlocked, sponsorable: @sponsorable, tier: @one_time_tier)
    old_expires_at = sponsorship.expires_at

    error = assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: @upgrade_tier, viewer: sponsorship.sponsor)
    end

    assert_equal "Cannot switch from one-time to monthly", error.message
    assert_equal @one_time_tier, sponsorship.reload.tier
    assert_equal old_expires_at, sponsorship.expires_at
    refute_predicate sponsorship, :locked?
  end

  test "does not instrument sponsor_sponsorship_tier_change audit log event for same tier" do
    events = subscribe "sponsors.sponsor_sponsorship_tier_change"
    Sponsors::UpdateSponsorshipTier.call(@sponsorship, new_tier: @tier, viewer: @sponsor)
    assert_nil events.pop
  end

  test "does not update subscribable_selected_at when subscription item fails to save" do
    old_subscribable_selected_at = @sponsorship.subscribable_selected_at
    PaymentMethod.any_instance.stubs(:valid_payment_token?).returns(false)

    travel_to(1.day.from_now) do
      assert_raises(Sponsors::UpdateSponsorship::UnprocessableError) do
        Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier)
      end

      refute_nil old_subscribable_selected_at
      assert_equal old_subscribable_selected_at, @sponsorship.reload.subscribable_selected_at
    end
  end

  test "enqueues a job to invite sponsor to the new tier's repo when changing to a tier with a repo" do
    tier_with_repo = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)

    perform_enqueued_jobs(only: [GrantSponsorsOnlyRepositoryAccessJob]) do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: tier_with_repo)
    end

    repository_invitation = RepositoryInvitation
      .for_invitee(@sponsor.id)
      .for_repository(tier_with_repo.repository_id)
      .first
    sponsorship_repository = SponsorshipRepository
      .for_tier(tier_with_repo.id)
      .for_sponsor(@sponsor.id)
      .first

    assert_performed_jobs(1, only: [GrantSponsorsOnlyRepositoryAccessJob])
    refute_nil repository_invitation
    refute_nil sponsorship_repository
  end

  test "does not enqueue a job to invite a sponsor to the new tier's repository if the new tier does not have a repository" do
    tier_without_repo = create(:sponsors_tier, :published, sponsors_listing: @listing)

    assert_no_enqueued_jobs(only: GrantSponsorsOnlyRepositoryAccessJob) do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: tier_without_repo)
    end
  end

  test "does not enqueue a job to invite a sponsor to the new tier's repository if the new tier and the previous tier have the same repository" do
    org = create(:organization, :sponsorable, admin: @sponsorable)
    repo = create(:private_repository, owner: org)
    previous_tier = create(:sponsors_tier, :published, sponsors_listing: @listing, repository: repo)
    new_tier = create(:sponsors_tier, :published, sponsors_listing: @listing, repository: repo)
    sponsorship = create(:sponsorship, sponsorable: @sponsorable, tier: previous_tier)
    sponsor = sponsorship.sponsor

    assert_no_enqueued_jobs(only: GrantSponsorsOnlyRepositoryAccessJob) do
      Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: sponsor, new_tier: new_tier)
    end
  end

  test "instruments sponsorship tier change if tier changed" do
    monthly_price_in_cents = @listing.sponsors_tiers.pluck(:monthly_price_in_cents).max + 1_00
    other_tier = create :sponsors_tier, :published, listing: @listing,
      monthly_price_in_cents: monthly_price_in_cents,
      yearly_price_in_cents: monthly_price_in_cents * 12
    old_subscribable_selected_at = @sponsorship.subscribable_selected_at

    events = subscribe "sponsors.sponsor_sponsorship_tier_change"
    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      sponsorship_id: @sponsorship.id,
      current_tier_id: other_tier.id,
      current_tier_monthly_amount_in_cents: other_tier.monthly_price_in_cents,
      previous_tier_id: @tier.id,
      public: true,
      frequency: "recurring",
      active: true,
      sponsor: @sponsor.login,
      sponsor_id: @sponsor.id,
      payment_source: "github",
    }

    assert_no_difference(-> { Sponsorship.count }) do
      travel_to(1.day.from_now) do
        Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: other_tier)
      end
    end

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
    refute_equal old_subscribable_selected_at, @sponsorship.reload.subscribable_selected_at
  end

  test "publishes tier changes to hydro", skip_enterprise: true do
    now = Time.parse("2018-01-01")

    travel_to(now) do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier)

      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(@sponsorship.reload),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        previous_tier: Hydro::EntitySerializer.sponsors_tier(@tier),
        current_tier: Hydro::EntitySerializer.sponsors_tier(@upgrade_tier),
      }

      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipTierChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipTierChange")

      # Verify no create/cancel message sent for a tier change:
      assert_hydro_messages(count: 0, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  test "raises an error if no viewer is provided" do
    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: nil, new_tier: @tier)
    end
  end

  test "raises an error if tier is in draft" do
    draft_tier = create(:sponsors_tier, :draft, sponsors_listing: @listing)

    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: draft_tier)
    end
  end

  test "raises an error if provided tier belongs to different sponsorable" do
    other_tier = create(:sponsors_tier, :approved_sponsors_listing)
    refute_equal other_tier.sponsorable, @sponsorship.sponsorable

    assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: other_tier)
    end
  end

  test "raises an error if the new tier exceeds an invoiced sponsor's balance" do
    stub_credit_balance(@tier.monthly_price_in_cents) do
      invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
      sponsorship = create(:sponsorship, sponsor: invoiced_org, sponsorable: @sponsorable, tier: @tier)

      assert_raises Sponsors::UpdateSponsorship::UnprocessableError do
        Sponsors::UpdateSponsorshipTier.call(sponsorship, viewer: invoiced_org.admin, new_tier: @upgrade_tier)
      end
    end
  end

  test "raises an error if viewer cannot admin sponsorship" do
    rando = create(:user, :verified)
    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: rando, new_tier: @tier)
    end
  end

  test "raises an error if viewer cannot see sponsorship" do
    other_private_sponsorship = create(:sponsorship, :private, sponsorable: @sponsorable)
    assert_raises Sponsors::UpdateSponsorship::ForbiddenError do
      Sponsors::UpdateSponsorshipTier.call(other_private_sponsorship, viewer: @sponsor, new_tier: @tier)
    end
  end

  test "supports delayed upgrade via future active_on date" do
    bill_on = GitHub::Billing.today + 7.days

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier, active_on: bill_on)

    assert_predicate @sponsorship.reload, :has_pending_activation?
    assert_equal bill_on, @sponsorship.pending_activation_date
    assert_equal @upgrade_tier, @sponsorship.tier
  end

  test "supports updating to same tier via future active_on date" do
    # this is used to support billing changes...we don't want to modify the tier, but we do want to schedule an
    # activation that will use a different billable entity (e.g. org -> enterprise)
    bill_on = GitHub::Billing.today + 7.days

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @tier, active_on: bill_on)

    assert_predicate @sponsorship.reload, :has_pending_activation?
    assert_equal bill_on, @sponsorship.pending_activation_date
    assert_equal @tier, @sponsorship.tier
  end

  test "does nothing if updating to same tier and active_on date not in the future" do
    bill_on = GitHub::Billing.today

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @tier, active_on: bill_on)

    refute_predicate @sponsorship.reload, :has_pending_activation?
    assert_nil @sponsorship.pending_activation_date
    assert_equal @tier, @sponsorship.tier
  end

  test "updates immediately when active_on date is today" do
    bill_on = GitHub::Billing.today

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier, active_on: bill_on)

    refute_predicate @sponsorship.reload, :has_pending_activation?
    assert_equal @upgrade_tier, @sponsorship.tier
  end

  test "updates immediately when active_on date is in the past" do
    bill_on = GitHub::Billing.today - 7.days

    Sponsors::UpdateSponsorshipTier.call(@sponsorship, viewer: @sponsor, new_tier: @upgrade_tier, active_on: bill_on)

    refute_predicate @sponsorship.reload, :has_pending_activation?
    assert_equal @upgrade_tier, @sponsorship.tier
  end
end
