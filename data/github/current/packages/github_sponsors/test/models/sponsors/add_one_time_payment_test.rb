# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsAddOneTimePaymentTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::ZuoraTestHelper
  include DogstatsTestHelpers

  fixtures do
    @listing = create(:sponsors_listing, :with_valid_contact_for_billing, :approved, :with_stripe_account)
    @sponsorable = @listing.sponsorable
    @recurring_tier = create(:sponsors_tier, :published, :recurring, sponsors_listing: @listing)
    @one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @listing)
    @custom_one_time_tier = create(:sponsors_tier, :custom, :one_time, sponsors_listing: @listing)
    @sponsor = create(:credit_card_user, :with_valid_contact_for_billing, :verified, billed_on: 2.days.from_now.to_date)
    @plan_subscription = create(:billing_plan_subscription, user: @sponsor, zuora_subscription_number: "123")
    @sponsor.reload
    @invoiced_org_admin = create(:user, :verified)
    @invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
      admin: @invoiced_org_admin)
    @enterprise_org_admin = create(:user, :verified)
    @self_serve_enterprise = create(:business, :with_valid_contact_for_billing, :with_credit_card, owners: [@enterprise_org_admin])
    @owned_org = create(:organization, admin: @enterprise_org_admin)
    @self_serve_enterprise.add_organization(@owned_org)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  if GitHub.spamminess_check_enabled?
    test "disallows sponsorship from a spammy user" do
      spammer = create(:spammy_user, :verified)
      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(sponsor: spammer, tier: @one_time_tier, viewer: spammer)
      end
      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end

    test "disallows sponsorship from a spammy organization" do
      non_spammy_org_admin = create(:user, :verified)
      spammy_org = create(:credit_card_organization, :spammy, admin: non_spammy_org_admin)
      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(sponsor: spammy_org, tier: @one_time_tier, viewer: non_spammy_org_admin)
      end
      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end
  end

  test "raises if the sponsorable is blocked by the sponsor" do
    @sponsor.block(@sponsorable)
    error = assert_raises Sponsors::CreateSponsorship::ForbiddenError do
      Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor)
    end
    assert_equal "You can't perform that action at this time.", error.message
  end

  test "raises if the given tier is for a different sponsorable" do
    other_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::AddOneTimePayment.call(tier: other_tier, sponsor: @sponsor, sponsorable: @sponsorable,
        viewer: @sponsor)
    end
    assert_equal "Could not create sponsorship: Tier is not @#{@sponsorable}'s", error.message
  end

  test "raises if the sponsor is blocked by the sponsorable" do
    blocked_user = create(:credit_card_user, :verified)
    @sponsorable.block(blocked_user)
    error = assert_raises Sponsors::CreateSponsorship::ForbiddenError do
      Sponsors::AddOneTimePayment.call(sponsor: blocked_user, tier: @one_time_tier,
        viewer: @sponsor)
    end
    assert_equal "You can't perform that action at this time.", error.message
  end

  test "raises if the sponsor does not have a verified email" do
    sponsor = create(:credit_card_user)
    error = assert_raises Sponsors::CreateSponsorship::ForbiddenError do
      Sponsors::AddOneTimePayment.call(viewer: sponsor, sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)
    end
    assert_equal "You need a verified email address in order to sponsor anyone.", error.message
  end

  test "raises if the sponsor does not have a payment method" do
    sponsor = create(:verified_user)
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::AddOneTimePayment.call(sponsor: sponsor, viewer: sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)
    end
    assert_equal "Please add a payment method before checking out.", error.message
  end

  test "raises for one-time sponsorship if the sponsor uses PayPal" do
    sponsor = create(:paypal_customer_account).user
    sponsor.emails.first.verify!

    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::AddOneTimePayment.call(sponsor: sponsor, viewer: sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier)
    end

    assert_equal "GitHub Sponsors no longer accepts PayPal. Update your payment method to be able to sponsor.",
      error.message
  end

  test "raises for concurrent one-time payment if the sponsor uses PayPal" do
    customer_account = create(:paypal_customer_account)
    sponsor = customer_account.user
    create(:billing_plan_subscription, user: sponsor, customer: customer_account.customer)
    sponsor.emails.first.verify!
    create(:sponsorship, sponsor: sponsor, sponsorable: @sponsorable, tier: @recurring_tier)

    error = assert_no_difference(["Billing::SubscriptionItem.count", "Sponsorship.count"]) do
      assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(sponsor: sponsor, viewer: sponsor, sponsorable: @sponsorable,
          tier: @one_time_tier)
      end
    end

    assert_equal "GitHub Sponsors no longer accepts PayPal. Update your payment method to be able to sponsor.",
      error.message
  end

  test "raises if an org admin tries to sponsor the org before the profile is approved" do
    sponsorable_org = create(:organization, :sponsorable, admin: @sponsor)
    listing = sponsorable_org.sponsors_listing
    tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
    listing.update!(state: :draft)

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_no_difference -> { Sponsorship.count } do
        assert_raises Sponsors::CreateSponsorship::UnprocessableError do
          Sponsors::AddOneTimePayment.call(
            sponsorable: sponsorable_org,
            tier: tier,
            sponsor: @sponsor,
            viewer: @sponsor,
          )
        end
      end
    end

    assert_equal "Could not create sponsorship: Sponsors profile must be approved", error.message
  end

  test "raises if blocked by trust system and feature flag enabled" do
    GitHub.flipper[:sponsors_enforce_trust_system].enable

    sponsorable_org = create(:organization, :sponsorable, admin: @sponsor)
    listing = sponsorable_org.sponsors_listing
    tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
    tier_above_limit = create(:sponsors_tier, :exceeds_untrusted_sponsorship_limit,
      sponsors_listing: listing,
    )
    create(:sponsors_activity,
      sponsor: @sponsor,
      sponsorable: sponsorable_org,
      sponsors_tier: tier_above_limit,
    )

    assert_predicate @sponsor.trust_level_as_sponsor, :untrusted?
    assert_predicate sponsorable_org.trust_level_as_sponsorable, :untrusted?

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_no_difference -> { Sponsorship.count } do
        assert_raises Sponsors::CreateSponsorship::ForbiddenError do
          Sponsors::AddOneTimePayment.call(
            sponsorable: sponsorable_org,
            tier: tier,
            sponsor: @sponsor,
            viewer: @sponsor,
          )
        end
      end
    end

    assert_equal "This sponsorship cannot be made at this time. "\
      "Please reach out to support for more details.", error.message
  end

  test "raises if a recurring sponsor still has a one-time payment processing to the sponsorable" do
    sponsorship = create(:sponsorship)
    sponsor = sponsorship.sponsor
    sponsorable = sponsorship.sponsorable
    one_time_tier = create(:sponsors_tier, :one_time, sponsors_listing: sponsorable.sponsors_listing)
    create(:sponsors_activity, :one_time, sponsor: sponsor, sponsorable: sponsorable)

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_no_difference -> { Sponsorship.count } do
        assert_raises Sponsors::CreateSponsorship::UnprocessableError do
          Sponsors::AddOneTimePayment.call(
            sponsorable: sponsorable,
            sponsor: sponsor,
            viewer: sponsor,
            tier: one_time_tier
          )
        end
      end
    end
  end

  test "raises if a one-time sponsor still has a one-time payment processing to the sponsorable" do
    sponsorship = create(:sponsorship, :one_time)
    sponsor = sponsorship.sponsor
    sponsorable = sponsorship.sponsorable
    create(:sponsors_activity, :one_time, sponsor: sponsor, sponsorable: sponsorable)

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_no_difference -> { Sponsorship.count } do
        assert_raises Sponsors::CreateSponsorship::UnprocessableError do
          Sponsors::AddOneTimePayment.call(
            sponsorable: sponsorable,
            sponsor: sponsor,
            viewer: sponsor,
            tier: sponsorship.tier
          )
        end
      end
    end
  end

  test "creates a subscription item if a recurring, Zuora-based invoiced sponsorship exists" do
    stub_credit_balance do
      original_sponsorship = create(:sponsorship, :sponsors_invoiced, sponsor: @invoiced_org, tier: @recurring_tier)

      subscription_item = assert_difference -> { Billing::SubscriptionItem.count } do
        Sponsors::AddOneTimePayment.call(
          sponsor: @invoiced_org,
          tier: @one_time_tier,
          viewer: @invoiced_org_admin,
          sponsorable: @sponsorable,
        )
      end

      refute_nil subscription_item
      assert_instance_of Billing::SubscriptionItem, subscription_item
      assert_predicate subscription_item, :active?
      assert_equal @one_time_tier, subscription_item.subscribable
      assert_equal @invoiced_org.sponsors_plan_subscription, subscription_item.plan_subscription
    end
  end

  test "creates a subscription item on the existing Sponsors-specific plan subscription if a recurring sponsorship exists on that plan subscription" do
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor,
      customer: @sponsor.customer)
    original_sponsorship = create(:sponsorship, sponsor: @sponsor, tier: @recurring_tier)

    subscription_item = Sponsors::AddOneTimePayment.call(
      sponsor: @sponsor,
      tier: @one_time_tier,
      viewer: @sponsor,
      sponsorable: @sponsorable
    )

    refute_nil subscription_item
    assert_instance_of Billing::SubscriptionItem, subscription_item
    assert_predicate subscription_item.reload, :active?
    assert_equal @one_time_tier, subscription_item.subscribable
    assert_equal sponsors_plan_sub, subscription_item.plan_subscription
  end

  test "raises if blocked by trust system and a recurring sponsorship exists and feature flag enabled" do
    GitHub.flipper[:sponsors_enforce_trust_system].enable

    original_sponsorship = create(:sponsorship, :with_activity, sponsor: @sponsor, tier: @recurring_tier)
    tier_above_limit = create(:sponsors_tier, :one_time, :exceeds_untrusted_sponsorship_limit,
      sponsors_listing: @sponsorable.sponsors_listing,
    )
    create(:sponsors_activity,
      sponsor: @sponsor,
      sponsorable: @sponsorable,
      sponsors_tier: tier_above_limit,
    )

    assert_predicate @sponsor.trust_level_as_sponsor, :untrusted?
    assert_predicate @sponsorable.trust_level_as_sponsorable, :untrusted?

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_raises Sponsors::CreateSponsorship::ForbiddenError do
        Sponsors::AddOneTimePayment.call(
          sponsor: @sponsor,
          tier: tier_above_limit,
          viewer: @sponsor,
          sponsorable: @sponsorable
        )
      end
    end

    assert_equal "This sponsorship cannot be made at this time. "\
    "Please reach out to support for more details.", error.message
  end

  test "does not update the sponsorship if an active recurring sponsorship exists" do
    original_sponsorship = create(:sponsorship, sponsor: @sponsor, tier: @recurring_tier)
    Sponsors::AddOneTimePayment.call(
      tier: @one_time_tier,
      sponsor: @sponsor,
      viewer: @sponsor,
      sponsorable: @sponsorable
    )

    assert_equal @recurring_tier, original_sponsorship.reload.tier
  end

  # https://github.com/github/sponsors/issues/3446
  test "updates the sponsorship if an inactive recurring sponsorship exists" do
    original_sponsorship = create(:sponsorship, :inactive, sponsor: @sponsor, tier: @recurring_tier)
    Sponsors::AddOneTimePayment.call(
      tier: @one_time_tier,
      sponsor: @sponsor,
      viewer: @sponsor,
      sponsorable: @sponsorable
    )

    assert_equal @one_time_tier, original_sponsorship.reload.tier
  end

  test "creates a subscription item on Sponsors-specific plan subscription if an inactive one-time sponsorship exists" do
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor,
      customer: @sponsor.customer)
    original_sponsorship = create(:sponsorship, :inactive, sponsor: @sponsor, tier: @one_time_tier)
    plan_subscription_item = sponsors_plan_sub.subscription_items.first
    refute_nil plan_subscription_item
    assert_equal plan_subscription_item, original_sponsorship.subscription_item

    assert_equal @one_time_tier, plan_subscription_item.subscribable
    assert_equal 0, plan_subscription_item.quantity
    assert_equal @sponsor, plan_subscription_item.user

    sponsorship = Sponsors::AddOneTimePayment.call(
      tier: @one_time_tier,
      sponsor: @sponsor,
      viewer: @sponsor,
      sponsorable: @sponsorable
    )

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    assert_equal 1, plan_subscription_item.reload.quantity
    assert_equal @one_time_tier, sponsorship.tier
    assert_equal sponsors_plan_sub, sponsorship.plan_subscription
  end

  test "creates a sponsorship record for invoiced org with sponsorship-specific Zuora account" do
    stub_credit_balance do
      sponsorship = assert_difference(["Billing::SubscriptionItem.count", "Sponsorship.count"]) do
        Sponsors::AddOneTimePayment.call(
          sponsor: @invoiced_org,
          tier: @one_time_tier,
          viewer: @invoiced_org_admin,
          sponsorable: @sponsorable,
        )
      end

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      assert_equal @invoiced_org, sponsorship.sponsor
      assert_equal @one_time_tier, sponsorship.tier
      assert_equal @sponsorable, sponsorship.sponsorable
      assert_predicate sponsorship, :privacy_public?
      assert_predicate sponsorship, :is_sponsor_opted_in_to_email?
      assert_predicate sponsorship, :active?
      assert_predicate sponsorship, :locked?
      assert_predicate sponsorship, :skip_proration?
      refute_nil sponsorship.expires_at
      refute_predicate sponsorship, :expired?
      subscription_item = sponsorship.subscription_item
      refute_nil subscription_item
      assert_equal @invoiced_org.sponsors_plan_subscription, subscription_item.plan_subscription
      assert_equal @one_time_tier, subscription_item.subscribable
      assert_predicate subscription_item, :active?
    end
  end

  test "creates a sponsorship record and subscription item tied to custom one-time tier" do
    sponsorship = assert_difference -> { Sponsorship.count } do
      Sponsors::AddOneTimePayment.call(
        tier: @custom_one_time_tier,
        sponsor: @custom_one_time_tier.creator,
        viewer: @custom_one_time_tier.creator,
        sponsorable: @sponsorable,
      )
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    assert_predicate sponsorship, :privacy_public?
    assert_predicate sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship, :active?
    assert_predicate sponsorship, :locked?
    refute_predicate sponsorship, :recurring_payment?
    assert_predicate sponsorship, :skip_proration?
    assert_equal @sponsorable, sponsorship.sponsorable
    assert_equal @custom_one_time_tier.creator, sponsorship.sponsor
    subscription_item = sponsorship.subscription_item
    assert_equal @custom_one_time_tier, subscription_item.subscribable
    assert_equal subscription_item.subscribable_id, sponsorship.subscribable_id
    assert_equal @sponsorable.id, sponsorship.sponsorable_id
    refute_nil sponsorship.expires_at
    refute_predicate sponsorship, :expired?
    refute_nil sponsorship.activated_at
  end

  test "always skips proration when making a one-time sponsorship" do
    freeze_time do
      sponsorship = assert_difference -> { Sponsorship.count } do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
          viewer: @sponsor)
      end

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      assert_equal Time.now.utc.to_s, sponsorship.subscribable_selected_at.to_s
      assert_predicate sponsorship, :active?
      assert_predicate sponsorship, :locked?
      refute_predicate sponsorship, :recurring_payment?
      assert_predicate sponsorship, :skip_proration?
      assert_equal @sponsorable, sponsorship.sponsorable
      assert_equal @sponsor, sponsorship.sponsor
      assert_equal @one_time_tier, sponsorship.subscription_item.subscribable
      assert_equal sponsorship.subscription_item.subscribable_id, sponsorship.subscribable_id
      assert_equal @sponsorable.id, sponsorship.sponsorable_id
      refute_nil sponsorship.expires_at
      assert_equal Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.from_now.end_of_day.to_s,
        sponsorship.expires_at.to_s
      refute_nil sponsorship.activated_at
    end
  end

  test "deactivates the subscription item on Sponsors-specific plan subscription when the sponsorship cannot be saved" do
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor,
      customer: @sponsor.customer)
    Sponsorship.any_instance.stubs(:save).returns(false)

    assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::AddOneTimePayment.call(sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier, viewer: @sponsor)
    end

    subscription_item = Billing::SubscriptionItem.find_by(plan_subscription: sponsors_plan_sub,
      subscribable: @one_time_tier)
    refute_nil subscription_item
    refute_predicate subscription_item, :active?
  end

  test "reports if the sponsorship cannot be saved" do
    Sponsorship.any_instance.stubs(:save).returns(false)

    assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::AddOneTimePayment.call(sponsor: @sponsor, sponsorable: @sponsorable,
        tier: @one_time_tier, viewer: @sponsor)
    end

    assert_dogstats_increment :at_least_one, "sponsors.create_sponsorship.failure"
  end

  test "reports when the sponsorship cannot be saved and the subscription item cannot be updated on the Sponsors-specific plan subscription" do
    Sponsorship.any_instance.stubs(:save).returns(false)
    Billing::SubscriptionItem.any_instance.expects(:update).with(quantity: 0).returns(false)
    error = T.let(nil, T.nilable(StandardError))

    assert_difference(-> { Billing::PlanSubscription.sponsors_purpose.count }) do
      error = assert_raises(Sponsors::CreateSponsorship::UnprocessableError) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, sponsorable: @sponsorable,
          tier: @one_time_tier, viewer: @sponsor)
      end
    end

    assert_match /unable to deactivate subscription item/, T.must(error).message
    sponsors_plan_sub = @sponsor.reload_sponsors_plan_subscription
    refute_nil sponsors_plan_sub
    subscription_item = Billing::SubscriptionItem.find_by(plan_subscription: sponsors_plan_sub,
      subscribable: @one_time_tier)
    refute_nil subscription_item
    assert_predicate T.must(subscription_item).reload, :active?
  end

  test "creates locked sponsorship when using a one-time custom tier" do
    freeze_time do
      sponsorship = assert_difference -> { Sponsorship.count } do
        Sponsors::AddOneTimePayment.call(
          tier: @custom_one_time_tier,
          sponsor: @custom_one_time_tier.creator,
          viewer: @custom_one_time_tier.creator,
          sponsorable: @sponsorable,
        )
      end

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      assert_equal Time.now.utc.to_s, sponsorship.subscribable_selected_at.to_s
      assert_predicate sponsorship, :active?
      assert_predicate sponsorship, :locked?
      assert_predicate sponsorship, :one_time_payment?
      assert_predicate sponsorship, :skip_proration?,
        "should have skipped proration on one-time sponsorship, even without specifying"
      assert_equal @sponsorable, sponsorship.sponsorable
      assert_equal @custom_one_time_tier.creator, sponsorship.sponsor
      assert_equal @custom_one_time_tier, sponsorship.tier
      assert_equal @custom_one_time_tier, sponsorship.subscription_item.subscribable
      refute_nil sponsorship.expires_at
      assert_equal Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.from_now.end_of_day.to_s,
        sponsorship.expires_at.to_s
      refute_nil sponsorship.activated_at
    end
  end

  test "marks potential sponsorship as having a sponsorship created" do
    potential_sponsorship = create(:potential_sponsorship, :ready_for_sponsorship, potential_sponsor: @sponsor)
    sponsorable = potential_sponsorship.potential_sponsorable
    tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: sponsorable.sponsors_listing)

    assert_difference(-> { Sponsorship.count }) do
      Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: tier, viewer: @sponsor,
        sponsorable: sponsorable)
    end

    assert_predicate potential_sponsorship.reload, :sponsorship_created?
  end

  test "does not modify potential sponsorship with a different potential sponsor" do
    other_potential_sponsorship = create(:potential_sponsorship, :ready_for_sponsorship) # not from @sponsor
    sponsorable = other_potential_sponsorship.potential_sponsorable
    tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: sponsorable.sponsors_listing)

    assert_difference(-> { Sponsorship.count }) do
      Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: tier, viewer: @sponsor,
        sponsorable: sponsorable)
    end

    assert_predicate other_potential_sponsorship.reload, :sponsors_listing_created?,
      "should not have marked potential sponsorship as sponsorship_created when sponsor differs"
  end

  test "creates locked sponsorship when using a one-time published tier" do
    freeze_time do
      sponsorship = assert_difference -> { Sponsorship.count } do
        Sponsors::AddOneTimePayment.call(tier: @one_time_tier, sponsor: @sponsor, sponsorable: @sponsorable,
          viewer: @sponsor)
      end

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      assert_equal Time.now.utc.to_s, sponsorship.subscribable_selected_at.to_s
      assert_predicate sponsorship, :active?
      assert_predicate sponsorship, :locked?
      assert_predicate sponsorship, :one_time_payment?
      assert_predicate sponsorship, :skip_proration?
      assert_equal @sponsorable, sponsorship.sponsorable
      assert_equal @sponsor, sponsorship.sponsor
      assert_equal @one_time_tier, sponsorship.tier
      assert_equal @one_time_tier, sponsorship.subscription_item.subscribable
      refute_nil sponsorship.expires_at
      assert_equal Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.from_now.end_of_day.to_s,
        sponsorship.expires_at.to_s
      refute_nil sponsorship.activated_at
    end
  end

  test "creates an invoiced sponsorship record without a subscription item" do
    create_events = subscribe "sponsors.sponsor_sponsorship_create"
    payment_complete_events = subscribe "sponsors.sponsor_sponsorship_payment_complete"
    expiration = Date.current + 2.days

    invoiced_sponsor = create(:invoiced_organization)
    invoiced_transfer = build(:invoiced_sponsorship_transfer,
      sponsors_listing: @listing,
      sponsor: invoiced_sponsor,
      stripe_connect_account: @listing.active_stripe_connect_account,
      expires_at: expiration,
    )
    assert_nil invoiced_transfer.transfer_created_at
    invoiced_tier = build(:sponsors_tier, :invoiced,
      sponsors_listing: @listing,
      creator: invoiced_sponsor,
    )

    sponsorship = assert_difference -> { Sponsorship.count } do
      Sponsors::AddOneTimePayment.call(sponsorable: @sponsorable, sponsor: invoiced_sponsor,
        invoiced_transfer: invoiced_transfer, tier: invoiced_tier, viewer: invoiced_transfer.actor,
        via_bulk_sponsorship: true)
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    assert_predicate sponsorship, :active?
    assert_predicate sponsorship, :manual_invoiced?
    assert_equal sponsorship.expires_at, expiration
    assert_predicate invoiced_tier.reload, :persisted?
    assert_predicate invoiced_transfer.reload, :persisted?
    assert_equal invoiced_transfer.id, sponsorship.invoiced_sponsorship_transfer.id
    assert_nil sponsorship.subscription_item
    refute_nil sponsorship.activated_at
    assert_nil sponsorship.paid_at, "should not set paid_at on sponsorship when transfer_created_at not " \
      "set on invoiced transfer"

    refute_nil create_event = create_events.pop, "a creation event was expected"
    assert_equal sponsorship.id, create_event.payload[:sponsorship_id]
    refute_nil payment_complete_event = payment_complete_events.pop, "a payment complete event was expected"
    assert_equal sponsorship.id, payment_complete_event.payload[:sponsorship_id]
    assert payment_complete_event.payload[:via_bulk_sponsorship]
  end

  test "logs create/cancel Hydro event for new invoiced sponsorship" do
    expiration = Date.current + 2.days

    invoiced_sponsor = create(:invoiced_organization)
    invoiced_transfer = build(:invoiced_sponsorship_transfer,
      sponsors_listing: @listing,
      sponsor: invoiced_sponsor,
      stripe_connect_account: @listing.active_stripe_connect_account,
      expires_at: expiration,
    )
    assert_nil invoiced_transfer.transfer_created_at
    actor = invoiced_transfer.actor
    invoiced_tier = build(:sponsors_tier, :invoiced,
      sponsors_listing: @listing,
      creator: invoiced_sponsor,
    )
    listing = invoiced_tier.sponsors_listing

    sponsorship = assert_difference -> { Sponsorship.count } do
      Sponsors::AddOneTimePayment.call(sponsorable: @sponsorable, sponsor: invoiced_sponsor,
        invoiced_transfer: invoiced_transfer, tier: invoiced_tier, viewer: actor)
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    message = {
      actor: Hydro::EntitySerializer.user(actor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(listing),
      tier: Hydro::EntitySerializer.sponsors_tier(invoiced_tier),
      matchable: false,
      action: :CREATE,
      first_time_sponsor: true,
      first_time_sponsorable: true,
      invoiced: true,
      payment_source: :GITHUB,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        listing.stafftools_metadata,
      ),
    }
    assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
  end

  test "logs payment complete Hydro event for new invoiced sponsorship" do
    freeze_time

    expiration = Date.current + 2.days

    invoiced_sponsor = create(:invoiced_organization)
    invoiced_transfer = build(:invoiced_sponsorship_transfer,
      sponsors_listing: @listing,
      sponsor: invoiced_sponsor,
      stripe_connect_account: @listing.active_stripe_connect_account,
      expires_at: expiration,
    )
    assert_nil invoiced_transfer.transfer_created_at
    actor = invoiced_transfer.actor
    invoiced_tier = build(:sponsors_tier, :invoiced,
      sponsors_listing: @listing,
      creator: invoiced_sponsor,
    )

    sponsorship = assert_difference -> { Sponsorship.count } do
      Sponsors::AddOneTimePayment.call(sponsorable: @sponsorable, sponsor: invoiced_sponsor,
        invoiced_transfer: invoiced_transfer, tier: invoiced_tier, viewer: actor)
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    message = {
      request_context: nil,
      actor: Hydro::EntitySerializer.user(actor),
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      tier: Hydro::EntitySerializer.sponsors_tier(invoiced_tier),
      matchable: false,
      first_time_sponsor: true,
      first_payment: true,
      first_time_sponsorable: true,
      invoiced: true,
      completed_at: Time.current,
      payment_source: :GITHUB,
    }
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
  end

  test "raises for invoiced sponsorships without a transfer" do
    invoiced_sponsor = create(:invoiced_organization)
    invoiced_transfer = build(:invoiced_sponsorship_transfer,
      sponsors_listing: @listing,
      sponsor: invoiced_sponsor,
      stripe_connect_account: @listing.active_stripe_connect_account,
    )
    invoiced_tier = build(:sponsors_tier, :invoiced,
      sponsors_listing: @listing,
      creator: invoiced_sponsor,
    )

    assert_no_difference -> { Sponsorship.count } do
      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(
          sponsor: invoiced_sponsor,
          sponsorable: @sponsorable,
          invoiced_transfer: nil,
          tier: invoiced_tier,
          viewer: invoiced_transfer.actor,
        )
      end

      assert_includes error.message, "An invoiced transfer is required"
    end
  end

  test "raises for invoiced sponsorships if transfer is invalid" do
    invoiced_sponsor = create(:invoiced_organization)
    invoiced_transfer = build(:invoiced_sponsorship_transfer,
      sponsors_listing: @listing,
      sponsor: invoiced_sponsor,
      stripe_connect_account: @listing.active_stripe_connect_account,
      expires_at: (Date.current - 1.day).to_s,
    )
    invoiced_tier = build(:sponsors_tier, :invoiced,
      sponsors_listing: @listing,
      creator: invoiced_sponsor,
    )

    refute_predicate invoiced_transfer, :valid?

    assert_no_difference -> { Sponsorship.count } do
      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(
          sponsor: invoiced_sponsor,
          sponsorable: @sponsorable,
          invoiced_transfer: invoiced_transfer,
          tier: invoiced_tier,
          viewer: invoiced_transfer.actor,
        )
      end

      assert_includes error.message, "Expires at must be a valid date in the future"
    end
  end

  test "instruments sponsorship creation for a brand new one-time sponsorship" do
    events = subscribe "sponsors.sponsor_sponsorship_create"

    sponsorship = assert_difference("events.size") do
      assert_difference(-> { Sponsorship.count }) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
          viewer: @sponsor)
      end
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      sponsorship_id: sponsorship.id,
      current_tier_id: @one_time_tier.id,
      current_tier_monthly_amount_in_cents: @one_time_tier.monthly_price_in_cents,
      active: true,
      sponsor: @sponsor.login,
      sponsor_id: @sponsor.id,
      public: true,
      frequency: "one_time",
      payment_source: "github",
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "synchronizes sponsor's existing Sponsors-specific plan subscription by default" do
    sponsorship = T.let(nil, T.nilable(Sponsorship))
    assert_equal "free", @sponsor.plan_name
    create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor, customer: @sponsor.customer)

    assert_enqueued_with(
      job: SynchronizePlanSubscriptionJob,
      args: [
        { user_id: @sponsor.id, plan_name: "free_with_addons", purpose: "sponsors" },
        { user: @sponsor },
      ],
    ) do
      assert_no_difference(-> { Billing::PlanSubscription.count }) do
        sponsorship = Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor)
      end
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
  end

  test "synchronizes sponsor's new Sponsors-specific plan subscription by default" do
    sponsorship = T.let(nil, T.nilable(Sponsorship))
    assert_equal "free", @sponsor.plan_name
    assert_nil @sponsor.sponsors_plan_subscription

    assert_enqueued_with(
      job: SynchronizePlanSubscriptionJob,
      args: [
        { user_id: @sponsor.id, plan_name: "free_with_addons", purpose: "sponsors" },
        { user: @sponsor },
      ],
    ) do
      assert_difference(-> { Billing::PlanSubscription.sponsors_purpose.count }) do
        sponsorship = Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor)
      end
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    refute_nil @sponsor.reload_sponsors_plan_subscription
  end

  test "skips synchronizing sponsor's Sponsors-specific plan subscription due to the new subscription item when specified" do
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor,
      customer: @sponsor.customer, zuora_subscription_number: "456")
    assert_predicate sponsors_plan_sub, :has_external_subscription?
    Billing::SubscriptionItem.any_instance.expects(:synchronize_plan_subscription).never

    sponsorship = Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor,
      skip_sync: true)

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    assert_equal sponsors_plan_sub, sponsorship.subscription_item.plan_subscription
  end

  test "bumps expires_at and subscribable_selected_at when reactivating a sponsorship with a one-time tier" do
    travel_to "2023-11-14"
    sponsorship = travel_to(6.months.ago) do
      create(:sponsorship, :inactive, :one_time, sponsor: @sponsor, sponsorable: @sponsorable, tier: @one_time_tier)
    end
    old_tier_selected_at = sponsorship.subscribable_selected_at
    old_expiration = sponsorship.expires_at
    old_activated_at = sponsorship.activated_at
    refute_nil old_expiration

    freeze_time do
      new_tier = create(:sponsors_tier, :custom, :one_time, sponsors_listing: @listing, creator: @sponsor)

      assert_no_difference(-> { Sponsorship.count }) do
        Sponsors::AddOneTimePayment.call(tier: new_tier, sponsor: @sponsor, sponsorable: @sponsorable,
          viewer: @sponsor)
      end

      assert_predicate sponsorship.reload, :active?
      refute_equal old_tier_selected_at, sponsorship.subscribable_selected_at
      assert_equal Time.now.utc.to_s, sponsorship.subscribable_selected_at.to_s
      assert_equal new_tier, sponsorship.tier
      new_expiration = sponsorship.expires_at
      refute_nil new_expiration
      refute_equal old_expiration, new_expiration
      assert_equal Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS.days.from_now.end_of_day.to_s,
        new_expiration.to_s
      refute_nil sponsorship.activated_at
      refute_equal old_activated_at, sponsorship.activated_at
    end
  end

  # https://github.com/github/sponsors/issues/1913
  test "instruments sponsorship creation when an inactive one-time sponsorship becomes active again" do
    sponsorship = create(:sponsorship, :unlocked, :with_billing_transaction_and_line_item, sponsor: @sponsor,
      skip_proration: true, tier: @one_time_tier,
      is_sponsor_opted_in_to_email: true)
    old_tier_selected_at = sponsorship.subscribable_selected_at

    sponsorship.cancel(actor: @sponsor, force: true)

    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      sponsorship_id: sponsorship.id,
      current_tier_id: @one_time_tier.id,
      current_tier_monthly_amount_in_cents: @one_time_tier.monthly_price_in_cents,
      active: true,
      sponsor: @sponsor.login,
      sponsor_id: @sponsor.id,
      public: true,
      frequency: "one_time",
      payment_source: "github",
    }
    events = subscribe("sponsors.sponsor_sponsorship_create")

    assert_difference("events.size") do
      assert_no_difference(-> { Sponsorship.count }) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
          viewer: @sponsor)
      end
    end

    assert_predicate sponsorship.reload, :active?, "existing sponsorship should be made active"
    refute_equal old_tier_selected_at, sponsorship.subscribable_selected_at
    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "publishes sponsorship creation to hydro for a brand new sponsorship", skip_enterprise: true do
    now = Time.parse("2018-01-01")

    travel_to(now) do
      sponsorship = assert_difference(-> { Sponsorship.count }) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
          viewer: @sponsor)
      end

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        matchable: false,
        action: :CREATE,
        first_time_sponsor: true,
        first_time_sponsorable: true,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
        via_bulk_sponsorship: false,
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  # https://github.com/github/sponsors/issues/1913
  test "publishes sponsorship creation to hydro when re-sponsoring someone", skip_enterprise: true do
    sponsorship = create(:sponsorship, :inactive, sponsor: @sponsor, skip_proration: true,
      tier: @one_time_tier, is_sponsor_opted_in_to_email: true)
    now = Time.parse("2018-01-01")

    travel_to(now) do
      assert_no_difference(-> { Sponsorship.count }) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
          viewer: @sponsor)
      end

      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        matchable: false,
        action: :CREATE,
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
  end

  test "publishes sponsorship creation to hydro when sponsor is not a first-time sponsor", skip_enterprise: true do
    now = Time.parse("2018-01-01")
    # Create a different sponsorship first from the same sponsor:
    create(:sponsorship, sponsor: @sponsor)

    travel_to(now) do
      sponsorship = Sponsors::AddOneTimePayment.call(tier: @one_time_tier, sponsor: @sponsor,
        sponsorable: @sponsorable, viewer: @sponsor)

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        matchable: false,
        action: :CREATE,
        first_time_sponsor: false,
        first_time_sponsorable: true,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  test "publishes sponsorship creation that is matchable to hydro", skip_enterprise: true do
    time = Time.parse("2020-01-01")

    User.any_instance.stubs(:eligible_for_sponsorship_match?).returns(true)
    SponsorsListing.any_instance.stubs(:matchable?).returns(true)

    travel_to(time) do
      sponsorship = Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
        viewer: @sponsor)

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        matchable: true,
        action: :CREATE,
        first_time_sponsor: true,
        first_time_sponsorable: true,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  test "sponsorship where org is sponsor hydro is not matchable", skip_enterprise: true do
    time = Time.parse("2020-01-01")
    SponsorsListing.any_instance.stubs(:matchable?).returns(true)

    travel_to(time) do
      User.any_instance.stubs(:eligible_for_sponsorship_match?).returns(true)
      org = create(:credit_card_organization, :with_valid_contact_for_billing, admin: @sponsor)

      sponsorship = Sponsors::AddOneTimePayment.call(sponsor: org, tier: @one_time_tier,
        viewer: @sponsor)

      refute_nil sponsorship
      assert_instance_of Sponsorship, sponsorship
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
        matchable: false,
        action: :CREATE,
        first_time_sponsor: true,
        first_time_sponsorable: true,
        invoiced: false,
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
          @listing.stafftools_metadata,
        ),
        payment_source: :GITHUB,
      }
      assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  test "publishes sponsorship creation with a goal to hydro", skip_enterprise: true do
    goal = create(:sponsors_goal, :active, listing: @listing)
    @listing.reload

    sponsorship = Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier,
      viewer: @sponsor)

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
    message = {
      actor: Hydro::EntitySerializer.user(@sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@one_time_tier),
      matchable: false,
      action: :CREATE,
      goal: Hydro::EntitySerializer.sponsors_goal(goal),
      first_time_sponsor: true,
      first_time_sponsorable: true,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @listing.stafftools_metadata,
      ),
      payment_source: :GITHUB,
    }
    assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
  end

  test "sets payout_probation_started_at on the listing" do
    refute @listing.payout_probation_started_at

    Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor)

    refute_nil @listing.reload.payout_probation_started_at
  end

  test "doesn't override payout_probation_started_at if it's already set" do
    travel_to "2023-11-14"
    timestamp = 10.minutes.ago
    travel_to(timestamp) do
      Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor)
    end
    assert_equal timestamp.to_i, @listing.reload.payout_probation_started_at.to_i,
      "need payout_probation_started_at to be set to begin with"
    second_sponsor = create(:credit_card_user, :with_valid_contact_for_billing, :verified)

    Sponsors::AddOneTimePayment.call(sponsor: second_sponsor, tier: @one_time_tier, viewer: second_sponsor)

    assert_equal timestamp.to_i, @listing.reload.payout_probation_started_at.to_i,
      "expected payout_probation_started_at to be #{timestamp}, was " \
      "#{@listing.payout_probation_started_at}"
  end

  test "reactivates a inactive/previously cancelled sponsorship subscription item on Sponsors-specific plan subscription" do
    sponsor_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor,
      customer: @sponsor.customer)
    previous_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor, tier: @one_time_tier)
    assert_predicate previous_sponsorship, :active?
    previous_subscription_item = previous_sponsorship.subscription_item
    assert_equal sponsor_plan_sub, previous_subscription_item.plan_subscription

    Billing::SubscriptionItemUpdater.perform(
      subscribable: @one_time_tier,
      quantity: 0,
      sender: @sponsor,
      force: true,
      plan_subscription: sponsor_plan_sub,
    )

    refute_predicate previous_sponsorship.reload, :active?
    assert_equal 0, previous_subscription_item.reload.quantity

    assert_no_difference(["Sponsorship.count", "Billing::SubscriptionItem.count"]) do
      Sponsors::AddOneTimePayment.call(
        is_public: false,
        email_opt_in: false,
        sponsor: @sponsor,
        tier: @one_time_tier,
        viewer: @sponsor,
      )
    end

    assert_predicate previous_sponsorship.reload, :active?
    assert_equal 1, previous_subscription_item.reload.quantity
    assert_equal sponsor_plan_sub, previous_subscription_item.plan_subscription
  end

  test "reactivates a previously cancelled subscription on a new one-time tier" do
    max_tier_price = @listing.sponsors_tiers.pluck(:monthly_price_in_cents).max
    new_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @listing,
                      monthly_price_in_cents: max_tier_price * 2)
    previous_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor, tier: @one_time_tier)
    previous_subscription_item = previous_sponsorship.subscription_item
    assert_predicate previous_sponsorship, :active?

    Billing::SubscriptionItemUpdater.perform(
      subscribable: @one_time_tier,
      quantity: 0,
      sender: @sponsor,
      force: true,
      plan_subscription: previous_subscription_item.plan_subscription,
    )

    refute_predicate previous_sponsorship.reload, :active?
    assert_equal 0, previous_subscription_item.reload.quantity

    assert_no_difference "Sponsorship.count" do
      Sponsors::AddOneTimePayment.call(
        tier: new_tier,
        is_public: false,
        email_opt_in: false,
        sponsor: @sponsor,
        viewer: @sponsor,
      )
    end

    new_subscription_item = previous_sponsorship.reload.subscription_item
    refute_equal previous_subscription_item, new_subscription_item
    assert_predicate previous_sponsorship.reload, :active?
    assert_equal 0, previous_subscription_item.reload.quantity
    assert_equal 1, new_subscription_item.quantity
    assert_equal @one_time_tier, previous_subscription_item.subscribable
    assert_equal new_tier, new_subscription_item.subscribable
    assert_equal new_tier, previous_sponsorship.tier
    assert_equal new_subscription_item.subscribable_id, previous_sponsorship.subscribable_id
  end

  # See https://github.com/github/sponsors/issues/2475
  test "rolled back one-time sponsorships can be re-attempted a week later on Sponsors-specific plan subscription" do
    sponsorship = travel_to 7.days.ago do
      failed_sponsorship = assert_difference(-> { Billing::PlanSubscription.sponsors_purpose.count }) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, sponsorable: @sponsorable,
          tier: @one_time_tier, viewer: @sponsor)
      end
      assert_predicate failed_sponsorship, :active?
      refute_nil @sponsor.reload_sponsors_plan_subscription
      sponsor_item = failed_sponsorship.subscription_item
      plan_sub = sponsor_item.plan_subscription
      assert_predicate plan_sub, :sponsors_purpose?

      Billing::SubscriptionItemUpdater.perform(
        subscribable: @one_time_tier,
        quantity: 0,
        sender: @sponsor,
        force: true,
        plan_subscription: plan_sub,
      )

      failed_sponsorship
    end

    refute_predicate sponsorship.reload, :active?

    Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: @one_time_tier, viewer: @sponsor)

    assert_predicate sponsorship.reload.subscription_item, :billable?
    assert_equal @sponsor.sponsors_plan_subscription, sponsorship.subscription_item.plan_subscription
  end

  test "subscribable_selected_at is updated when selecting same (expired) one-time tier on Sponsors-specific plan subscription" do
    listing = create(:sponsors_listing, :approved, :with_one_time_tier)
    one_time_tier = listing.published_sponsors_tiers.one_time.first

    sponsorship = travel_to((Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS + 1).days.ago) do
      assert_difference(-> { Billing::PlanSubscription.sponsors_purpose.count }) do
        Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: one_time_tier, viewer: @sponsor,
          is_public: false, email_opt_in: false)
      end
    end

    refute_nil @sponsor.reload_sponsors_plan_subscription
    old_selected_at = sponsorship.subscribable_selected_at
    assert_predicate sponsorship, :active?
    assert_equal @sponsor.sponsors_plan_subscription, sponsorship.subscription_item.plan_subscription

    DeactivateExpiredSponsorshipsJob.perform_now

    Sponsors::AddOneTimePayment.call(sponsor: @sponsor, tier: one_time_tier, viewer: @sponsor,
      is_public: false, email_opt_in: false)

    assert_predicate sponsorship.reload, :active?
    refute_equal old_selected_at, sponsorship.subscribable_selected_at
    assert_equal @sponsor.sponsors_plan_subscription, sponsorship.subscription_item.plan_subscription
  end

  test "raises if the sponsor is member org of invoiced enterprise" do
    enterprise = create(:business, owners: [@enterprise_org_admin])
    enterprise.enable_feature(:sponsors_self_serve_enterprise)
    org = create(:organization, admin: @enterprise_org_admin)
    enterprise.add_organization(org)

    org.grant_sponsorships_access(actor: @enterprise_org_admin)
    org.reload

    error = assert_no_difference -> { Sponsorship.count } do
      assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(sponsor: org, sponsorable: @sponsorable, viewer: @enterprise_org_admin, tier: @one_time_tier)
      end
    end

    assert_equal "Please contact support to sponsor #{@one_time_tier.sponsorable} via invoice.", error.message
  end

  test "raises if the sponsor is member org of self-serve enterprise without permissions" do
    @self_serve_enterprise.enable_feature(:sponsors_self_serve_enterprise)

    error = assert_no_difference -> { Sponsorship.count } do
      assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::AddOneTimePayment.call(sponsor: @owned_org, sponsorable: @sponsorable, viewer: @enterprise_org_admin, tier: @one_time_tier)
      end
    end
    assert_equal "This organization does not have permission to create sponsorships. Please contact support.", error.message
  end

  test "creates sponsorship when sponsor is member org of self-serve enterprise with permissions" do
    @self_serve_enterprise.enable_feature(:sponsors_self_serve_enterprise)
    @owned_org.grant_sponsorships_access(actor: @enterprise_org_admin)

    assert_difference -> { Sponsorship.count } do
      Sponsors::AddOneTimePayment.call(sponsor: @owned_org, sponsorable: @sponsorable, viewer: @enterprise_org_admin, tier: @one_time_tier)
    end

    sponsorship = Sponsorship.last
    assert_predicate sponsorship, :active?
    assert_predicate sponsorship, :locked?
    refute_predicate sponsorship, :recurring_payment?
    assert_equal @sponsorable, T.must(sponsorship).sponsorable
    assert_equal @owned_org, T.must(sponsorship).sponsor
    assert_equal @one_time_tier, T.must(T.must(sponsorship).subscription_item).subscribable
    assert_equal @owned_org.id, T.must(T.must(sponsorship).subscription_item).organization_id
    refute_nil T.must(sponsorship).expires_at
    refute_nil T.must(sponsorship).activated_at
  end
end if GitHub.sponsors_enabled?
