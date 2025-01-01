# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsCreateRecurringSponsorshipTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ZuoraTestHelper
  include DogstatsTestHelpers

  fixtures do
    @sponsorable = create(:credit_card_user, :verified)
    @listing = create(:sponsors_listing, :approved, :with_stripe_account, sponsorable: @sponsorable)
    @tier = @listing.default_tier
    @tier_with_repo = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
    @sponsor = create(:credit_card_user, :with_valid_contact_for_billing, :verified, billed_on: 2.days.from_now.to_date)
    @custom_tier = create(:sponsors_tier, :custom, sponsors_listing: @listing, creator: @sponsor)
    @plan_subscription = create(:billing_plan_subscription, :zuora, user: @sponsor)
    @sponsor.reload
    @invoiced_org_admin = create(:user, :verified)
    @invoiced_org = create(:invoiced_organization, :sponsors_invoiced, admin: @invoiced_org_admin)
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
        Sponsors::CreateRecurringSponsorship.call(sponsor: spammer, tier: @tier, viewer: spammer)
      end
      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end

    test "disallows sponsorship from a spammy organization" do
      non_spammy_org_admin = create(:user, :verified)
      spammy_org = create(:credit_card_organization, :spammy, admin: non_spammy_org_admin)
      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::CreateRecurringSponsorship.call(sponsor: spammy_org, tier: @tier, viewer: non_spammy_org_admin)
      end
      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end

    test "disallows reactivation of inactive sponsorship by a spammer" do
      sponsorship = create(:sponsorship, :inactive, sponsorable: @sponsorable, tier: @tier)
      spammer = sponsorship.sponsor
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { spammer.mark_as_spammy }

      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::CreateRecurringSponsorship.call(sponsor: spammer, tier: @tier, viewer: spammer)
      end

      assert_equal "Your account is flagged and unable to make purchases. Please contact support to have your " \
        "account reviewed.", error.message
    end
  end

  test "raises if the sponsorable is blocked by the sponsor" do
    @sponsor.block(@sponsorable)
    error = assert_raises Sponsors::CreateSponsorship::ForbiddenError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end
    assert_equal "You can't perform that action at this time.", error.message
  end

  test "raises if the given tier is for a different sponsorable" do
    other_tier = create(:sponsors_tier, :approved_sponsors_listing)
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(tier: other_tier, sponsor: @sponsor, sponsorable: @sponsorable,
        viewer: @sponsor)
    end
    assert_equal "Could not create sponsorship: Tier is not @#{@sponsorable}'s", error.message
  end

  test "raises if the sponsor is blocked by the sponsorable" do
    blocked_user = create(:credit_card_user, :verified)
    @sponsorable.block(blocked_user)
    error = assert_raises Sponsors::CreateSponsorship::ForbiddenError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: blocked_user, tier: @tier, viewer: @sponsor)
    end
    assert_equal "You can't perform that action at this time.", error.message
  end

  test "raises if the sponsor does not have a verified email" do
    sponsor = create(:credit_card_user)
    error = assert_raises Sponsors::CreateSponsorship::ForbiddenError do
      Sponsors::CreateRecurringSponsorship.call(viewer: sponsor, tier: @tier, sponsor: sponsor)
    end
    assert_equal "You need a verified email address in order to sponsor anyone.", error.message
  end

  test "raises if the sponsor does not have a payment method" do
    sponsor = create(:verified_user)
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: sponsor, viewer: sponsor, tier: @tier)
    end
    assert_equal "Please add a payment method before checking out.", error.message
  end

  test "raises if the sponsor uses PayPal" do
    sponsor = create(:paypal_customer_account).user
    sponsor.emails.first.verify!
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: sponsor, viewer: sponsor, tier: @tier)
    end
    assert_equal "GitHub Sponsors no longer accepts PayPal. Update your payment method to be able to sponsor.",
      error.message
  end

  test "raises if the sponsor is member org of invoiced enterprise" do
    enterprise = create(:business, owners: [@enterprise_org_admin])
    enterprise.enable_feature(:sponsors_self_serve_enterprise)
    org = create(:organization, admin: @enterprise_org_admin)
    enterprise.add_organization(org)

    org.grant_sponsorships_access(actor: @enterprise_org_admin)
    org.reload

    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: org, viewer: @enterprise_org_admin, tier: @tier)
    end
    assert_equal "Please contact support to sponsor #{@tier.sponsorable} via invoice.", error.message
  end

  test "raises if the sponsor is member org of self-serve enterprise without permissions" do
    @self_serve_enterprise.enable_feature(:sponsors_self_serve_enterprise)

    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @owned_org, viewer: @enterprise_org_admin, tier: @tier)
    end
    assert_equal "This organization does not have permission to create sponsorships. Please contact support.", error.message
  end

  test "creates sponsorship when sponsor is member org of self-serve enterprise with permissions" do
    @self_serve_enterprise.enable_feature(:sponsors_self_serve_enterprise)
    @owned_org.grant_sponsorships_access(actor: @enterprise_org_admin)

    assert_difference -> { Sponsorship.count } do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @owned_org, viewer: @enterprise_org_admin, tier: @tier)
    end

    sponsorship = Sponsorship.last
    assert_predicate sponsorship, :active?
    refute_predicate sponsorship, :locked?
    assert_predicate sponsorship, :recurring_payment?
    assert_equal @sponsorable, T.must(sponsorship).sponsorable
    assert_equal @owned_org, T.must(sponsorship).sponsor
    assert_equal @tier, T.must(T.must(sponsorship).subscription_item).subscribable
    assert_equal @owned_org.id, T.must(T.must(sponsorship).subscription_item).organization_id
    assert_nil T.must(sponsorship).expires_at
    refute_nil T.must(sponsorship).activated_at
  end

  context "#enqueue_pending_sponsorship_email_job" do
    test "enqueues a job to email sponsors if sponsorship's state is pending when FF enabled" do
      @sponsor.enable_feature(:sponsors_pending_sponsorships)

      assert_enqueued_with(job: SendPendingSponsorshipEmailJob) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
      end
    end

    test "does not enqueue a job to email sponsors if sponsorship's state is pending when FF disabled" do
      @sponsor.disable_feature(:sponsors_pending_sponsorships)

      assert_no_enqueued_jobs(only: SendPendingSponsorshipEmailJob) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
      end
    end

    test "does not enqueue a job to email sponsors if sponsorship's state is active when FF enabled" do
      @sponsor.enable_feature(:sponsors_pending_sponsorships)

      assert_no_enqueued_jobs(only: SendPendingSponsorshipEmailJob) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor, state: :active_test)
      end
    end
  end

  test "raises if end date is specified and sponsor is not an organization" do
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, viewer: @sponsor, tier: @tier,
        end_date: 3.months.from_now.to_date)
    end
    assert_equal "You cannot set an end date for this sponsorship.", error.message
  end

  test "raises if end date is today" do
    freeze_time do
      error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @invoiced_org, viewer: @invoiced_org_admin, tier: @tier,
          end_date: Date.current)
      end
      assert_equal "Please choose an end date in the future.", error.message
    end
  end

  test "raises if end date is in the past" do
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @invoiced_org, viewer: @invoiced_org_admin, tier: @tier,
        end_date: 1.week.ago.to_date)
    end
    assert_equal "Please choose an end date in the future.", error.message
  end

  test "raises if active_on is not the next billing date" do
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(
        sponsor: @invoiced_org,
        viewer: @invoiced_org_admin,
        tier: @tier,
        active_on: @invoiced_org.next_billing_date + 1.day,
      )
    end
    billing_date = @invoiced_org.next_billing_date.strftime("%B %e, %Y")
    assert_equal "Sponsorship can only be scheduled to begin on the sponsor's next billing date, #{billing_date}.",
      error.message
  end

  test "raises if active_on is a date in the past" do
    error = assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(
        sponsor: @invoiced_org,
        viewer: @invoiced_org_admin,
        tier: @tier,
        active_on: @invoiced_org.next_billing_date - 1.day,
      )
    end
    billing_date = @invoiced_org.next_billing_date.strftime("%B %e, %Y")
    assert_equal "Sponsorship can only be scheduled to begin on the sponsor's next billing date, #{billing_date}.",
      error.message
  end

  test "raises if blocked by trust system when feature flag enabled" do
    GitHub.flipper[:sponsors_enforce_trust_system].enable

    sponsorable_org = create(:organization, :sponsorable, admin: @sponsor)
    listing = sponsorable_org.sponsors_listing
    tier = create(:sponsors_tier, :published, sponsors_listing: listing)
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
          Sponsors::CreateRecurringSponsorship.call(
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

  test "allows invoiced org with sponsorship-specific Zuora account to set end date" do
    stub_credit_balance do

      end_date = 3.months.from_now.to_date

      assert_difference -> { Sponsorship.count } do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @invoiced_org, viewer: @invoiced_org_admin, tier: @tier,
          end_date: end_date)
      end

      sponsorship = Sponsorship.last
      assert_equal @invoiced_org, T.must(sponsorship).sponsor
      assert_equal @tier, T.must(sponsorship).tier
      refute_nil T.must(sponsorship).expires_at
      assert_equal end_date, T.must(T.must(sponsorship).expires_at).to_date
      assert_predicate sponsorship, :active?
      refute_nil T.must(sponsorship).activated_at
      assert_predicate sponsorship, :privacy_public?
      assert_predicate sponsorship, :is_sponsor_opted_in_to_email?
      refute_predicate sponsorship, :locked?
      refute_predicate sponsorship, :skip_proration?
      assert_equal @sponsorable, T.must(sponsorship).sponsorable
      subscription_item = T.must(sponsorship).subscription_item
      assert_equal @tier, T.must(subscription_item).subscribable
    end
  end

  test "raises if an org admin tries to sponsor the org before the profile is approved" do
    sponsorable_org = create(:organization, :sponsorable, admin: @sponsor)
    listing = sponsorable_org.sponsors_listing
    listing.update!(state: :draft)

    error = assert_no_difference -> { Billing::SubscriptionItem.count } do
      assert_no_difference -> { Sponsorship.count } do
        assert_raises Sponsors::CreateSponsorship::UnprocessableError do
          Sponsors::CreateRecurringSponsorship.call(
            tier: listing.default_tier,
            sponsor: @sponsor,
            viewer: @sponsor,
          )
        end
      end
    end

    assert_equal "Could not create sponsorship: Sponsors profile must be approved", error.message
  end

  test "creates a sponsorship record and subscription item tied to custom tier" do
    assert_difference -> { Sponsorship.count } do
      Sponsors::CreateRecurringSponsorship.call(
        tier: @custom_tier,
        sponsor: @custom_tier.creator,
        viewer: @custom_tier.creator,
      )
    end

    sponsorship = Sponsorship.last
    assert_predicate sponsorship, :privacy_public?
    assert_predicate sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship, :active?
    refute_predicate sponsorship, :locked?
    assert_predicate sponsorship, :recurring_payment?
    refute_predicate sponsorship, :skip_proration?
    assert_nil T.must(sponsorship).paid_at, "should not yet be marked as paid"
    assert_equal @sponsorable, T.must(sponsorship).sponsorable
    assert_equal @custom_tier.creator, T.must(sponsorship).sponsor
    subscription_item = T.must(sponsorship).subscription_item
    assert_equal @custom_tier, T.must(subscription_item).subscribable
    assert_equal T.must(subscription_item).subscribable_id, T.must(sponsorship).subscribable_id
    assert_equal @sponsorable.id, T.must(sponsorship).sponsorable_id
    assert_nil T.must(sponsorship).expires_at
    refute_nil T.must(sponsorship).activated_at
  end

  test "creates a sponsorship record and subscription item tied to published tier" do
    assert_difference -> { Sponsorship.count } do
      Sponsors::CreateRecurringSponsorship.call(
        is_public: false,
        email_opt_in: false,
        pay_prorated: true,
        sponsor: @sponsor,
        tier: @tier,
        viewer: @sponsor,
      )
    end

    sponsorship = Sponsorship.last
    assert_predicate sponsorship, :privacy_private?
    refute_predicate sponsorship, :is_sponsor_opted_in_to_email?
    assert_predicate sponsorship, :active?
    refute_predicate sponsorship, :locked?
    assert_predicate sponsorship, :recurring_payment?
    refute_predicate sponsorship, :skip_proration?
    assert_nil T.must(sponsorship).paid_at, "should not yet be marked as paid"
    assert_equal @sponsorable, T.must(sponsorship).sponsorable
    assert_equal @sponsor, T.must(sponsorship).sponsor
    assert_equal @tier, T.must(T.must(sponsorship).subscription_item).subscribable
    assert_equal T.must(T.must(sponsorship).subscription_item).subscribable_id, T.must(sponsorship).subscribable_id
    assert_equal @sponsorable.id, T.must(sponsorship).sponsorable_id
    assert_nil T.must(sponsorship).expires_at
    refute_nil T.must(sponsorship).activated_at
  end

  test "deactivates the subscription item on Sponsors-specific plan subscription when the sponsorship cannot be saved" do
    Sponsorship.any_instance.stubs(:save).returns(false)
    mock_errors = mock("errors")
    mock_errors.stubs(:full_messages).returns(["Oh no!", "Where am I?"])
    Sponsorship.any_instance.stubs(:errors).returns(mock_errors)

    expected_log = {
      "Body" => "Sponsors subscription item rollback initiated",
      "gh.catalog_service" => "github/github_sponsors",
      "gh.sponsor.id" => @sponsor.id,
      "gh.sponsors_tier.id" => @tier.id,
      "exception.details" => "Could not create sponsorship: Oh no!, Where am I?"
    }

    assert_logged(**expected_log) do
      assert_difference(-> { Billing::PlanSubscription.sponsors_purpose.count }) do
        assert_raises Sponsors::CreateSponsorship::UnprocessableError do
          Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
        end
      end
    end

    sponsors_plan_sub = @sponsor.reload_sponsors_plan_subscription
    refute_nil sponsors_plan_sub
    subscription_item = Billing::SubscriptionItem.find_by(plan_subscription: sponsors_plan_sub, subscribable: @tier)
    refute_nil subscription_item
    refute_predicate subscription_item, :active?

    report = Failbot.reports.detect do |report|
      report.fetch("exception_detail")
        .map { |ex| ex["value"] }
        .include?("Sponsors subscription item rollback initiated")
    end

    refute_nil report, "Should generate Sentry report"
    assert_equal "Could not create sponsorship: Oh no!, Where am I?", report.dig("sensitive_context", "errors")
  end

  test "reports if the sponsorship cannot be saved" do
    Sponsorship.any_instance.stubs(:save).returns(false)

    assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end

    assert_dogstats_increment 1, "sponsors.create_sponsorship.failure"
  end

  test "reports when the sponsorship cannot be saved and the subscription item cannot be updated on Sponsors-specific plan subscription" do
    Sponsorship.any_instance.stubs(:save).returns(false)
    Billing::SubscriptionItem.any_instance.expects(:update).with(quantity: 0).returns(false)
    sponsors_plan_sub = create(:billing_plan_subscription, :zuora, user: @sponsor, purpose: :sponsors)

    error = assert_raises(Sponsors::CreateSponsorship::UnprocessableError) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end
    assert_match /unable to deactivate subscription item/, error.message

    subscription_item = Billing::SubscriptionItem.find_by(plan_subscription: sponsors_plan_sub, subscribable: @tier)
    refute_nil subscription_item
    assert_predicate T.must(subscription_item).reload, :active?
  end

  test "creates a sponsorship record with skip proration flag" do
    # skipping proration requires an existing sponsors-purpose plan subscription
    create(:billing_plan_subscription, :zuora, user: @sponsor, purpose: :sponsors)
    assert_difference -> { Sponsorship.count } do
      Sponsors::CreateRecurringSponsorship.call(pay_prorated: false, sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end

    sponsorship = Sponsorship.last
    assert_predicate sponsorship, :active?
    refute_predicate sponsorship, :locked?
    assert_predicate sponsorship, :recurring_payment?
    assert_predicate sponsorship, :skip_proration?
    assert_equal @sponsorable, T.must(sponsorship).sponsorable
    assert_equal @sponsor, T.must(sponsorship).sponsor
    assert_equal @tier, T.must(T.must(sponsorship).subscription_item).subscribable
    assert_nil T.must(sponsorship).expires_at
    refute_nil T.must(sponsorship).activated_at
  end

  test "instruments sponsorship creation for a brand new sponsorship" do
    events = subscribe "sponsors.sponsor_sponsorship_create"

    assert_difference("events.size") do
      assert_difference(-> { Sponsorship.count }) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
      end
    end

    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      sponsorship_id: T.must(Sponsorship.last).id,
      current_tier_id: @tier.id,
      current_tier_monthly_amount_in_cents: @tier.monthly_price_in_cents,
      active: true,
      sponsor: @sponsor.login,
      sponsor_id: @sponsor.id,
      public: true,
      frequency: "recurring",
      payment_source: "github",
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "marks potential sponsorship as having a sponsorship created" do
    potential_sponsorship = create(:potential_sponsorship, :ready_for_sponsorship, potential_sponsor: @sponsor)
    sponsorable = potential_sponsorship.potential_sponsorable
    tier = sponsorable.sponsors_listing.default_tier

    assert_difference(-> { Sponsorship.count }) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: tier, viewer: @sponsor,
        sponsorable: sponsorable)
    end

    assert_predicate potential_sponsorship.reload, :sponsorship_created?
  end

  test "synchronizes sponsor's Sponsors-specific plan subscription by default" do
    sponsorship = T.let(nil, T.nilable(Sponsorship))
    assert_equal "free", @sponsor.plan_name

    assert_enqueued_with(
      job: SynchronizePlanSubscriptionJob,
      args: [
        { user_id: @sponsor.id, plan_name: "free_with_addons", purpose: "sponsors" },
        { user: @sponsor },
      ],
    ) do
      sponsorship = Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
  end

  test "skips synchronizing the sponsor's Sponsors-specific plan subscription when specified" do
    sponsor = create(:credit_card_user, :with_valid_contact_for_billing, :verified)
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: sponsor,
      customer: sponsor.customer)
    SynchronizePlanSubscriptionJob.expects(:perform_later)
      .with({ user_id: sponsor.id, plan_name: sponsor.plan_name, purpose: "sponsors" }, user: @sponsor)
      .never

    sponsorship = Sponsors::CreateRecurringSponsorship.call(sponsor: sponsor, tier: @tier, viewer: sponsor,
      skip_sync: true)

    refute_nil sponsorship
    assert_instance_of Sponsorship, sponsorship
  end

  test "does not modify potential sponsorship with a different potential sponsor" do
    other_potential_sponsorship = create(:potential_sponsorship, :ready_for_sponsorship) # not from @sponsor
    sponsorable = other_potential_sponsorship.potential_sponsorable
    tier = sponsorable.sponsors_listing.default_tier

    assert_difference(-> { Sponsorship.count }) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: tier, viewer: @sponsor,
        sponsorable: sponsorable)
    end

    assert_predicate other_potential_sponsorship.reload, :sponsors_listing_created?,
      "should not have marked potential sponsorship as sponsorship_created when sponsor differs"
  end

  # https://github.com/github/sponsors/issues/1913
  test "instruments sponsorship creation when an inactive sponsorship becomes active again" do
    sponsorship = travel_to(1.year.ago) do
      create(:sponsorship, :with_billing_transaction_and_line_item, sponsor: @sponsor,
        skip_proration: true, tier: @tier,
        is_sponsor_opted_in_to_email: true)
    end
    old_tier_selected_at = sponsorship.subscribable_selected_at

    sponsorship.subscription_item.cancel!(actor: @sponsor, force: true)

    expected_payload = {
      sponsorable_user: @sponsorable.login,
      sponsorable_user_id: @sponsorable.id,
      actor: @sponsor.login,
      actor_id: @sponsor.id,
      user: @sponsor.login,
      user_id: @sponsor.id,
      sponsorship_id: sponsorship.id,
      current_tier_id: @tier.id,
      current_tier_monthly_amount_in_cents: @tier.monthly_price_in_cents,
      active: true,
      sponsor: @sponsor.login,
      sponsor_id: @sponsor.id,
      public: true,
      frequency: "recurring",
      payment_source: "github",
    }
    events = subscribe("sponsors.sponsor_sponsorship_create")

    assert_difference("events.size") do
      assert_no_difference(-> { Sponsorship.count }) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
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
      assert_difference(-> { Sponsorship.count }) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
      end

      sponsorship = Sponsorship.last
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@tier),
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

  test "publishes sponsorship creation to hydro for a sponsorship made in bulk", skip_enterprise: true do
    events = subscribe("sponsorship.added")

    assert_difference(-> { Sponsorship.count }) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor,
        via_bulk_sponsorship: true)
    end

    sponsorship = Sponsorship.last
    message = {
      actor: Hydro::EntitySerializer.user(@sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@tier),
      matchable: false,
      action: :CREATE,
      first_time_sponsor: true,
      first_time_sponsorable: true,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        @listing.stafftools_metadata,
      ),
      payment_source: :GITHUB,
      via_bulk_sponsorship: true,
    }
    assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    refute_nil event = events.pop, "an audit log event was expected"
    assert_equal({ subscription_item_id: T.must(sponsorship).subscription_item_id, sender_id: @sponsor.id,
      via_bulk_sponsorship: true }, event.payload)
  end

  # https://github.com/github/sponsors/issues/1913
  test "publishes sponsorship creation to hydro when re-sponsoring someone", skip_enterprise: true do
    # skipping proration requires an existing sponsors-purpose plan subscription
    create(:billing_plan_subscription, :zuora, user: @sponsor, purpose: :sponsors)
    sponsorship = create(:sponsorship, :inactive, sponsor: @sponsor, skip_proration: true,
      tier: @tier, is_sponsor_opted_in_to_email: true)
    now = Time.parse("2018-01-01")

    travel_to(now) do
      assert_no_difference(-> { Sponsorship.count }) do
        Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
      end

      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@tier),
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

  test "creates a Patreon sponsorship without a subscription item and instruments payment complete audit log and Hydro events" do
    @sponsor.enable_feature("sponsors_patreon")
    @sponsorable.enable_feature("sponsors_patreon")

    create(:sponsors_patreon_user, :sponsor, user: @sponsor)
    create(:sponsors_patreon_user, user: @sponsorable)

    create_events = subscribe "sponsors.sponsor_sponsorship_create"
    payment_complete_events = subscribe "sponsors.sponsor_sponsorship_payment_complete"

    freeze_time

    assert_difference -> { Sponsorship.count } do
      Sponsors::CreateRecurringSponsorship.call(
        sponsor: @sponsor,
        sponsorable: @sponsorable,
        viewer: @sponsor,
        payment_source: :patreon,
        tier: @custom_tier
      )
    end

    sponsorship = Sponsorship.last
    assert_predicate sponsorship, :active?
    assert_equal "patreon", T.must(sponsorship).payment_source
    assert_equal @custom_tier, T.must(sponsorship).tier
    assert_nil T.must(sponsorship).subscription_item
    refute_nil T.must(sponsorship).paid_at, "should have set payment time on new Patreon sponsorship"
    refute_nil create_event = create_events.pop, "a creation audit log event was expected"
    assert_equal T.must(sponsorship).id, create_event.payload[:sponsorship_id]
    refute_nil payment_complete_event = payment_complete_events.pop, "a payment complete audit log event was expected"
    assert_equal T.must(sponsorship).id, payment_complete_event.payload[:sponsorship_id]
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
    message = {
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      actor: Hydro::EntitySerializer.user(@sponsor),
      listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@custom_tier),
      matchable: false,
      first_time_sponsor: true,
      first_payment: true,
      first_time_sponsorable: true,
      invoiced: false,
      via_bulk_sponsorship: false,
      completed_at: Time.current,
      request_context: nil,
      payment_source: :PATREON,
    }
    assert_hydro_published(message, schema: "github.sponsors.v1.SponsorshipPaymentComplete")
  end

  # https://github.com/github/sponsors/issues/5249
  test "overrides sponsorship details and starts subscription when overriding a patreon sponsorship with a github sponsorship" do
    sponsorship = create(:sponsorship, :patreon, sponsor: @sponsor, sponsorable: @sponsorable, skip_proration: true)
    now = Time.parse("2018-01-01")

    assert_nil sponsorship.subscription_item

    reset_hydro

    travel_to(now) do
      new_sponsorship = assert_no_difference(-> { Sponsorship.count }) do
        assert_difference(-> { Billing::SubscriptionItem.count }) do
          Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
        end
      end

      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(new_sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@tier),
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

      assert_predicate new_sponsorship, :active?
      assert_equal new_sponsorship.payment_source, "github"
      assert_equal new_sponsorship.tier, @tier
      refute_nil new_sponsorship.subscription_item
      assert_equal @tier, new_sponsorship.subscription_item.subscribable
      assert_equal 1, new_sponsorship.subscription_item.quantity
    end
  end

  test "publishes sponsorship creation that is matchable to hydro", skip_enterprise: true do
    time = Time.parse("2020-01-01")
    User.any_instance.stubs(:eligible_for_sponsorship_match?).returns(true)
    SponsorsListing.any_instance.stubs(:matchable?).returns(true)

    travel_to(time) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)

      sponsorship = Sponsorship.last
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@tier),
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
    User.any_instance.stubs(:eligible_for_sponsorship_match?).returns(true)
    org = create(:credit_card_organization, :with_valid_contact_for_billing, admin: @sponsor)

    travel_to(time) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: org, tier: @tier, viewer: @sponsor)

      sponsorship = Sponsorship.last
      message = {
        actor: Hydro::EntitySerializer.user(@sponsor),
        request_context: nil,
        sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        tier: Hydro::EntitySerializer.sponsors_tier(@tier),
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

    Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)

    sponsorship = Sponsorship.last
    message = {
      actor: Hydro::EntitySerializer.user(@sponsor),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(@listing),
      tier: Hydro::EntitySerializer.sponsors_tier(@tier),
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

  test "does not create subscription item or sponsorship when user is self-sponsoring" do
    assert_no_difference(-> { Billing::SubscriptionItem.count }) do
      assert_no_difference(-> { Sponsorship.count }) do
        assert_raises("Sponsor cannot sponsor themselves") do
          Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsorable, tier: @tier, viewer: @sponsorable)
        end
      end
    end
  end

  test "sets payout_probation_started_at on the listing" do
    assert_nil @listing.payout_probation_started_at

    Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier,
      viewer: @sponsor)

    refute_nil @listing.reload.payout_probation_started_at
  end

  test "doesn't override payout_probation_started_at if it's already set" do
    travel_to "2023-11-13"
    timestamp = 10.minutes.ago

    travel_to(timestamp) do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end

    assert_equal timestamp.to_i, @listing.reload.payout_probation_started_at.to_i,
      "need payout_probation_started_at to be set to begin with"
    second_sponsor = create(:credit_card_user, :with_valid_contact_for_billing, :verified)

    Sponsors::CreateRecurringSponsorship.call(sponsor: second_sponsor, tier: @tier, viewer: second_sponsor)

    assert_equal timestamp.to_i, @listing.reload.payout_probation_started_at.to_i,
      "expected payout_probation_started_at to be #{timestamp}, was " \
      "#{@listing.payout_probation_started_at}"
  end

  test "reactivates a inactive/previously cancelled subscription on Sponsors-specific plan subscription" do
    sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor,
      customer: @sponsor.customer)
    previous_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor, tier: @tier)
    previous_subscription_item = previous_sponsorship.subscription_item
    assert_equal sponsors_plan_sub, previous_subscription_item.plan_subscription
    assert_predicate previous_sponsorship, :active?
    assert_equal 1, previous_subscription_item.quantity

    update = Billing::SubscriptionItemUpdater.perform(
      subscribable: @tier,
      quantity: 0,
      sender: @sponsor,
      force: true,
      plan_subscription: sponsors_plan_sub,
    )

    assert update.result.success, update.result.errors.inspect
    refute_predicate previous_sponsorship.reload, :active?
    assert_equal 0, previous_subscription_item.reload.quantity

    assert_no_difference "Sponsorship.count" do
      Sponsors::CreateRecurringSponsorship.call(
        is_public: false,
        email_opt_in: false,
        sponsor: @sponsor,
        tier: @tier,
        viewer: @sponsor,
      )
    end

    assert_predicate previous_sponsorship.reload, :active?
    assert_equal 1, previous_subscription_item.reload.quantity
  end

  test "reactivates a previously cancelled subscription on a new tier" do
    max_tier_price = @listing.sponsors_tiers.pluck(:monthly_price_in_cents).max
    new_tier = create(:sponsors_tier, :published, sponsors_listing: @listing,
      monthly_price_in_cents: max_tier_price * 2)
    previous_sponsorship = create(:sponsorship, sponsorable: @sponsorable, sponsor: @sponsor, tier: @tier)
    previous_subscription_item = previous_sponsorship.subscription_item
    assert_predicate previous_sponsorship, :active?

    Billing::SubscriptionItemUpdater.perform(
      subscribable: @tier,
      quantity: 0,
      sender: @sponsor,
      force: true,
      plan_subscription: previous_subscription_item.plan_subscription,
    )

    refute_predicate previous_sponsorship.reload, :active?
    assert_equal 0, previous_subscription_item.reload.quantity

    assert_no_difference "Sponsorship.count" do
      Sponsors::CreateRecurringSponsorship.call(
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
    assert_equal @tier, previous_subscription_item.subscribable
    assert_equal new_tier, new_subscription_item.subscribable
    assert_equal new_tier, previous_sponsorship.tier
    assert_equal new_subscription_item.subscribable_id, previous_sponsorship.subscribable_id
  end

  # https://github.com/github/sponsors/issues/2570
  test "reactivates a previously inactive one-time subscription on a new recurring tier" do
    sponsorship = travel_to((Sponsorship::DAYS_TO_SHOW_ONE_TIME_SPONSORS + 1).days.ago) do
      create(:sponsorship, :inactive, :one_time, sponsorable: @sponsorable, sponsor: @sponsor)
    end
    assert_predicate sponsorship, :expired?
    refute_nil sponsorship.expires_at

    assert_no_difference -> { Sponsorship.count } do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @tier, viewer: @sponsor)
    end

    refute_predicate sponsorship.reload, :expired?
    assert_nil sponsorship.expires_at
  end

  test "cancels the subscription item if the sponsorship fails to save" do
    Sponsorship.any_instance.stubs(:save).returns(false)

    assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @listing.default_tier, viewer: @sponsor)
    end

    subscription_item = Billing::SubscriptionItem.for_account(@sponsor).first
    assert_equal true, T.must(subscription_item).cancelled?
  end

  test "cancels subscription item if the Sponsors listing fails to update" do
    SponsorsListing.any_instance.stubs(:update).returns(false)

    assert_raises Sponsors::CreateSponsorship::UnprocessableError do
      Sponsors::CreateRecurringSponsorship.call(sponsor: @sponsor, tier: @listing.default_tier, viewer: @sponsor)
    end

    subscription_item = Billing::SubscriptionItem.for_account(@sponsor).first
    assert_equal true, T.must(subscription_item).cancelled?
  end
end if GitHub.sponsors_enabled?
