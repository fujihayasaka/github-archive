# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPendingPlanChangeTest < GitHub::TestCase
  include HydroTestHelpers
  include PageHelper

  context "hydro" do
    test "logs trial plan change event when a plan trial is present" do
      org = create(:organization, plan: "free")
      Billing::EnterpriseCloudTrial.new(org).create

      reset_hydro

      trial = Billing::PlanTrial.last
      T.must(T.must(trial).pending_plan_change).run

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(org.reload),
        trial_plan: "business_plus",
        new_plan: "free",
        trial_expired: true,
        user_initiated: false,
      }, schema: "github.billing.v0.TrialPlanChange")
    end
  end

  context "#run" do
    test "processes subscription item changes for a Business billable entity" do
      ghas_uuid = create(:billing_product_uuid, :advanced_security)
      plan_subscription = create(:billing_plan_subscription, :business_owned)
      business = plan_subscription.billable_entity
      subscription_item = create :billing_subscription_item,
        quantity: 3,
        subscribable: ghas_uuid,
        plan_subscription: plan_subscription
      change = create(:billing_pending_plan_change, :item_change_only, :business, customer: business.customer)
      create :billing_pending_subscription_item_change,
        subscribable: ghas_uuid,
        free_trial: false,
        pending_plan_change: change,
        quantity: 0,
        plan_subscription: plan_subscription
      change.reload
      Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

      assert_equal 3, subscription_item.quantity

      change.run

      subscription_item.reload
      assert_equal 0, subscription_item.quantity
    end

    test "does not call PlanSubscription#synchronize_later when skip_sync is true" do
      ghas_uuid = create(:billing_product_uuid, :advanced_security)
      plan_subscription = create(:billing_plan_subscription, :business_owned)
      business = plan_subscription.billable_entity
      subscription_item = create :billing_subscription_item,
        quantity: 3,
        subscribable: ghas_uuid,
        plan_subscription: plan_subscription
      change = create(:billing_pending_plan_change, :item_change_only, :business, customer: business.customer)
      create :billing_pending_subscription_item_change,
        subscribable: ghas_uuid,
        free_trial: false,
        pending_plan_change: change,
        quantity: 0,
        plan_subscription: plan_subscription
      change.reload
      Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

      assert_equal 3, subscription_item.quantity

      change.run(skip_sync: true)

      subscription_item.reload
      assert_equal 0, subscription_item.quantity
    end

    test "Only synchronizes once when there are multiple changes" do
      ghas_uuid = create(:billing_product_uuid, :advanced_security)
      plan_subscription = create(:billing_plan_subscription, :business_owned, :zuora_business)
      business = plan_subscription.billable_entity
      actor = business.owners.first
      subscription_item = create :billing_subscription_item,
        quantity: 3,
        subscribable: ghas_uuid,
        plan_subscription: plan_subscription
      change = business.pending_plan_changes.create!(
        active_on: GitHub::Billing.today,
        customer: business.customer,
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
        seats: 200,
        actor: actor
      )
      create :billing_pending_subscription_item_change,
        subscribable: ghas_uuid,
        free_trial: false,
        pending_plan_change: change,
        quantity: 0,
        plan_subscription: plan_subscription
      change.reload

      assert_equal User::BillingDependency::YEARLY_PLAN, business.plan_duration
      assert_equal User::BillingDependency::YEARLY_PLAN, plan_subscription.plan_duration
      assert_equal 100, business.seats
      assert_equal 3, subscription_item.quantity

      assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
        change.run
      end

      business.reload
      plan_subscription.reload
      subscription_item.reload

      assert_equal User::BillingDependency::MONTHLY_PLAN, business.plan_duration
      assert_equal User::BillingDependency::MONTHLY_PLAN, plan_subscription.plan_duration
      assert_equal 200, business.seats
      assert_equal 0, subscription_item.quantity
      assert change.reload.is_complete?
    end

    test "updates evaluation terms to corporate terms when in a trial" do
      org = create :organization, plan: "free", seats: 10
      org.terms_of_service.update(type: "Evaluation", actor: org.admins.first)
      Billing::EnterpriseCloudTrial.new(org).create
      change = Billing::PendingPlanChange.last

      T.must(change).run

      assert org.reload.terms_of_service.corporate?
    end

    test "updates user's plan with scheduled changes" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 10, 10)) do
        org = create :organization, plan: "free", seats: 10
        actor = create :user
        create(:billing_plan_subscription, :zuora, user: org)
        create :asset_status, owner: org, data_packs: 4
        change = org.pending_plan_changes.create!(
          active_on: GitHub::Billing.today,
          plan: GitHub::Plan.business,
          seats: 5,
          actor: actor,
        )
        change.run

        org.reload
        assert_equal GitHub::Plan.business, org.plan
        assert_equal 5, org.seats
        assert_equal org.plan, org.plan_subscription.plan

        change.reload
        assert change.is_complete?
        assert GitHub::Billing.today, change.active_on
      end
    end

    test "updates business's plan duration with scheduled changes" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 10, 10)) do
        business_plan_subscription = create(:billing_plan_subscription, :business_owned)
        business = business_plan_subscription.business
        actor = business.owners.first

        assert_equal User::BillingDependency::YEARLY_PLAN, business.plan_duration
        assert_equal User::BillingDependency::YEARLY_PLAN, business_plan_subscription.plan_duration

        change = business.pending_plan_changes.create!(
          active_on: GitHub::Billing.today,
          plan_duration: User::BillingDependency::MONTHLY_PLAN,
          actor: actor
        )
        change.run

        business.reload
        business_plan_subscription.reload
        assert_equal User::BillingDependency::MONTHLY_PLAN, business.plan_duration
        assert_equal User::BillingDependency::MONTHLY_PLAN, business_plan_subscription.plan_duration
        assert change.reload.is_complete?
      end
    end

    test "supports changing data packs" do
      user = create :credit_card_user
      actor = create :user
      status = create :asset_status, owner: user, data_packs: 4
      change = create :billing_pending_plan_change,
        data_packs: 2,
        plan: nil,
        plan_duration: nil,
        seats: nil,
        user: user,
        actor: actor

      change.run

      status.reload
      assert_equal 2, status.data_packs
    end

    test "downgrades to micro from small" do
      user = create :credit_card_user, plan: "small", billed_on: ::GitHub::Billing.today
      change = create :billing_pending_plan_change, user: user, plan: "micro", plan_duration: "month"

      change.run

      user.reload
      assert_equal "micro", user.plan.name
    end

    test "cancels seats and data packs" do
      org = create :credit_card_org, seats: 10
      create :asset_status, owner: org, data_packs: 4
      change = create :billing_pending_plan_change,
        data_packs: 0,
        plan: "diamond",
        seats: 0,
        user: org

      change.run

      org.reload
      assert_equal 0, org.data_packs
      assert_equal 0, org.seats
    end

    test "supports changing from free trial to paid plan" do
      user = create :credit_card_user
      listing_plan = create :marketplace_listing_plan,
        :published,
        monthly_price_in_cents: 10_00,
        has_free_trial: true,
        listing: create(:marketplace_listing, :verified)
      plan_subscription = create :billing_plan_subscription, user: user
      user.reload
      subscription_item = create :billing_subscription_item,
        subscribable: listing_plan,
        plan_subscription: plan_subscription
      change = create :billing_pending_plan_change,
        active_on: GitHub::Billing.today + 8.days, plan: nil, user: user, actor: user
      create :billing_pending_subscription_item_change,
        subscribable: listing_plan,
        free_trial: true,
        pending_plan_change: change,
        quantity: 4
      change.reload

      refute subscription_item.billable?

      change.run
      assert subscription_item.reload.billable?
    end

    test "updates item free_trial_ends_on and price when free trial is run" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 10, 23)) do
        user = create(:user)
        listing_plan = create :marketplace_listing_plan,
          :published, monthly_price_in_cents: 10_00, has_free_trial: true
        plan_subscription = create(:billing_plan_subscription, user: user)
        item = create :billing_subscription_item,
          subscribable: listing_plan, account: user, plan_subscription: plan_subscription
        pending_change = create :billing_pending_plan_change,
          active_on: GitHub::Billing.today + 14.days, plan: nil, user: user, actor: user
        create :billing_pending_subscription_item_change,
          subscribable: listing_plan,
          pending_plan_change: pending_change,
          quantity: 4,
          free_trial: true

        pending_change.run

        assert_equal GitHub::Billing.yesterday, item.reload.free_trial_ends_on
        assert_equal Billing::Money.new(40_00), item.reload.price
      end
    end

    # See https://github.com/github/sponsors/issues/1909
    test "handles multiple pending sponsorship changes" do
      sponsorship_date = GitHub::Billing.timezone.local(2020, 9, 19)
      change_date = sponsorship_date + 7.days
      run_date = change_date + 7.days

      pending_plan_change = T.let(nil, T.nilable(Billing::PendingPlanChange))
      sponsor = T.let(nil, T.nilable(User))

      first_sponsorship = T.let(nil, T.nilable(Sponsorship))
      first_high_tier = T.let(nil, T.nilable(SponsorsTier))
      first_low_tier = T.let(nil, T.nilable(SponsorsTier))

      second_sponsorship = T.let(nil, T.nilable(Sponsorship))
      second_high_tier = T.let(nil, T.nilable(SponsorsTier))
      second_low_tier = T.let(nil, T.nilable(SponsorsTier))

      travel_to sponsorship_date do
        sponsor = create(
          :credit_card_user,
          plan_subscription: create(:billing_plan_subscription),
          plan: GitHub::Plan.free_with_addons,
        )

        first_listing = create(:sponsors_listing, :approved, :with_tiers)
        first_high_tier, first_low_tier = first_listing.sponsors_tiers.highest_monthly_price_first.limit(2)

        second_listing = create(:sponsors_listing, :approved, :with_tiers)
        second_high_tier, second_low_tier = second_listing.sponsors_tiers.highest_monthly_price_first.limit(2)

        first_sponsorship = create(
          :sponsorship,
          sponsor: sponsor,
          sponsorable: first_listing.sponsorable,
          tier: first_high_tier,
        )
        second_sponsorship = create(
          :sponsorship,
          sponsor: sponsor,
          sponsorable: second_listing.sponsorable,
          tier: second_high_tier,
        )
      end

      first_sponsorship = T.must(first_sponsorship)
      second_sponsorship = T.must(second_sponsorship)
      sponsor = T.must(sponsor)

      travel_to change_date do
        Billing::SchedulePlanChange.run(
          active_on: run_date,
          account: sponsor,
          actor: sponsor,
          subscribable: first_low_tier,
          subscribable_quantity: 1,
          plan_subscription: first_sponsorship.plan_subscription
        )
        Billing::SchedulePlanChange.run(
          active_on: run_date,
          account: sponsor,
          actor: sponsor,
          subscribable: second_low_tier,
          subscribable_quantity: 1,
          plan_subscription: second_sponsorship.plan_subscription
        )
      end

      assert_predicate first_sponsorship, :active?
      assert_equal first_high_tier, first_sponsorship.tier,
        "first sponsorship should use high tier before change"

      assert_predicate second_sponsorship, :active?
      assert_equal second_high_tier, second_sponsorship.tier,
        "second sponsorship should use high tier before change"

      travel_to run_date do
        T.must(sponsor.pending_plan_changes.last).run
      end

      assert_predicate first_sponsorship.reload, :active?, "first sponsorship should still be active"
      assert_equal first_low_tier, first_sponsorship.tier,
        "first sponsorship should use low tier after change"

      assert_predicate second_sponsorship.reload, :active?, "second sponsorship should still be active"
      assert_equal second_low_tier, second_sponsorship.tier,
        "second sponsorship should use low tier after change"
    end

    test "increments attempts when run for org" do
      org = create :organization, plan: "free", seats: 10
      actor = create :user
      change = org.pending_plan_changes.create!(
        active_on: GitHub::Billing.today,
        plan: GitHub::Plan.pro,
        actor: actor,
      )
      assert_equal 0, change.attempts

      change.run

      assert_equal 1, change.reload.attempts
    end

    test "increments attempts when run for business" do
      business = create :business, :with_self_serve_payment
      actor = business.owners.first
      change = business.pending_plan_changes.create!(
        active_on: GitHub::Billing.today,
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
        actor: actor
      )
      assert_equal 0, change.attempts

      change.run

      assert_equal 1, change.reload.attempts
    end

    test "logs success to Datadog for user" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:credit_card_user, plan: "pro", billed_on: ::GitHub::Billing.today)
      change = create(:billing_pending_plan_change, user: user, plan: "free", plan_duration: "month")

      change.run

      increments = GitHub.dogstats.increments("account_management.pending_plan_change_run", tags: ["success:true"])
      assert_equal 1, increments.count
    end

    test "logs success to Datadog for business" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      business = create :business, :with_self_serve_payment
      change = create(:billing_pending_plan_change, customer: business.customer, plan_duration: "month")

      change.run

      increments = GitHub.dogstats.increments("account_management.pending_plan_change_run", tags: ["success:true"])
      assert_equal 1, increments.count
    end

    test "logs third failed attempt to Datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      3.times { org.add_member(create(:user)) }
      change = create(
        :billing_pending_plan_change,
        user: org,
        seats: 2,
        plan: GitHub::Plan.business_plus,
        attempts: 2,
      )

      change.run

      increments = GitHub.dogstats.increments("account_management.pending_plan_change_run", tags: ["success:false"])
      assert_equal 1, increments.count
    end

    test "does not log initial failed attempts to Datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      3.times { org.add_member(create(:user)) }
      change = create(
        :billing_pending_plan_change,
        user: org,
        seats: 2,
        plan: GitHub::Plan.business_plus,
      )

      RunPendingPlanChangeJob.perform_now(change)

      increments = GitHub.dogstats.increments("account_management.pending_plan_change_run", tags: ["success:false"])
      assert_equal 0, increments.count
    end

    test "disconnects enterprise connection after downgrade from business_plus" do
      org = create :credit_card_org,
        plan_duration: "month",
        plan: "business_plus",
        seats: 5
      actor = create :user
      enterprise_installation = create(:enterprise_installation, owner: org)
      integration, secret = enterprise_installation.create_github_app
      active_on = 1.month.from_now.to_date
      pending_plan_change = org.pending_plan_changes.create!(
        plan_duration: "year",
        plan: "business",
        seats: 10,
        active_on: active_on,
        actor: actor,
      )
      pending_plan_change.run

      assert_equal 0, org.enterprise_installations.count
      assert_equal 0, EnterpriseInstallation.where(id: enterprise_installation.id).count
      assert_equal 0, Integration.where(id: integration.id).count
    end

    test "disables notification restrictions after downgrade from business_plus" do
      org = create :credit_card_org,
        plan_duration: "month",
        plan: "business_plus",
        seats: 5
      actor = create :user
      active_on = 1.month.from_now.to_date

      create(:verifiable_domain, owner: org, verified: true)
      org.enable_notification_restrictions(actor: org)
      assert org.restrict_notifications_to_verified_domains?

      pending_plan_change = org.pending_plan_changes.create!(
        plan_duration: "year",
        plan: "business",
        seats: 10,
        active_on: active_on,
        actor: actor,
      )
      pending_plan_change.run

      refute org.restrict_notifications_to_verified_domains?
    end

    test "disables saml for the organization after downgrading from business_plus" do
      org = create(:business_plus_org)
      identity = create(:external_identity, org: org)
      user = identity.user
      actor = create :user
      provider = identity.provider

      assert_equal user.external_identities, [identity]
      assert_equal org.saml_provider, provider

      pending_plan_change = org.pending_plan_changes.create!(
        plan_duration: "year",
        plan: "business",
        seats: 10,
        active_on: 1.month.from_now.to_date,
        actor: actor,
      )

      perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
        pending_plan_change.run
      end

      assert_nil org.reload.saml_provider
      assert_empty user.reload.external_identities
    end

    test "disables IP allow list for the organization after downgrading from business_plus" do
      org = create :business_plus_org
      entry = create :ip_allowlist_entry, active: true, owner: org, allow_list_value: "1.2.3.4"
      org.enable_ip_allowlist actor: org.admins.first
      assert_predicate org, :ip_allowlist_enabled?

      pending_plan_change = org.pending_plan_changes.create!(
        plan_duration: "year",
        plan: "business",
        seats: 10,
        active_on: 1.month.from_now.to_date,
        actor: org.admins.first,
      )
      pending_plan_change.run

      refute_predicate org, :ip_allowlist_enabled?
      # IP allow list entries remain attached
      assert_same_elements [entry], org.ip_allowlist_entries
    end

    test "disables ssh certificate requirement when enabled and no longer eligible" do
      now = Time.now.utc
      Timecop.freeze(now) do
        # setup an org with a SSH certificate authority and the ssh certificate requirement enabled
        org = create(:organization, plan: "business_plus", seats: 1)
        ca = create(:ssh_certificate_authority, owner: org)
        org.enable_ssh_certificate_requirement(org)
        org.reload

        # verifiy initial state
        assert_predicate org, :ssh_certificate_requirement_enabled?

        # create a pending plan change to downgrade to free
        actor = create :user
        change = org.pending_plan_changes.create!(
          active_on: now - 1.day,
          plan: GitHub::Plan.business, # e.g. team plan
          actor: actor,
        )

        # verify the pending plan change runs
        assert_equal 0, change.attempts
        change.run
        assert_equal 1, change.reload.attempts

        # verify the ssh certificate requirement is now disabled
        org.reload
        refute_predicate org, :ssh_certificate_requirement_enabled?
      end
    end

    test "does not disable ssh certificate requirement when not enabled" do
      now = Time.now.utc
      Timecop.freeze(now) do
        org = create(:organization, plan: "business_plus", seats: 1)
        # verifiy initial state is not enabled
        refute_predicate org, :ssh_certificate_requirement_enabled?

        # create a pending plan change to downgrade to free
        actor = create :user
        change = org.pending_plan_changes.create!(
          active_on: now - 1.day,
          plan: GitHub::Plan.business, # e.g. team plan
          actor: actor,
        )

        # expect that disable_ssh_certificate_requirement is not called
        org.expects(:disable_ssh_certificate_requirement).never

        # verify the pending plan change runs
        assert_equal 0, change.attempts
        change.run
        assert_equal 1, change.reload.attempts

        # verify the ssh certificate requirement is now disabled
        org.reload
        refute_predicate org, :ssh_certificate_requirement_enabled?
      end
    end

    test "does not disable ssh certificate requirement when enabled and still eligible after downgrade" do
      now = Time.now.utc
      Timecop.freeze(now) do
        # setup an org with a SSH certificate authority and the ssh certificate requirement enabled
        # use an ID of a "grandfathered" plan to ensure the org is still eligible after downgrade
        org = create(:organization, plan: "business_plus", seats: 1, id: SshCertificateAuthority::GRANDFATHERED_ORG_IDS.first)
        ca = create(:ssh_certificate_authority, owner: org)
        org.enable_ssh_certificate_requirement(org)
        org.reload

        # verifiy initial state
        assert_predicate org, :ssh_certificate_requirement_enabled?

        # create a pending plan change to downgrade to free
        actor = create :user
        change = org.pending_plan_changes.create!(
          active_on: now - 1.day,
          plan: GitHub::Plan.business, # e.g. team plan
          actor: actor,
        )

        # verify the pending plan change runs
        assert_equal 0, change.attempts
        change.run
        assert_equal 1, change.reload.attempts

        # verify the ssh certificate requirement is still enabled
        org.reload
        assert_predicate org, :ssh_certificate_requirement_enabled?
      end
    end

    context "when a disabled user downgrades from pro to free" do
      test "payment methods are removed" do
        user = create(:credit_card_user, :with_billing_locked, plan: "pro")

        assert user.has_credit_card?

        change = create(:billing_pending_plan_change, user: user, plan: GitHub::Plan.free)
        change.run

        refute user.has_credit_card?
      end

      test "data packs are reset" do
        user = create(:billing_locked_user, plan: "pro")
        Asset::Status.create!(owner: user, asset_packs: 3)

        assert_equal 3, user.data_packs

        change = create(:billing_pending_plan_change, user: user, plan: GitHub::Plan.free)
        change.run

        assert_equal 0, user.data_packs
      end

      test "billing attempts is reset" do
        user = create(:billing_locked_user, plan: "pro", billing_attempts: 3)

        assert_equal 3, user.billing_attempts

        change = create(:billing_pending_plan_change, user: user, plan: GitHub::Plan.free)
        change.run

        assert_equal 0, user.billing_attempts
      end

      test "the account is enabled" do
        user = create(:billing_locked_user, plan: "pro")

        assert user.disabled?

        change = create(:billing_pending_plan_change, user: user, plan: GitHub::Plan.free)
        change.run

        assert user.enabled?
      end

      test "billed on is reset" do
        user = create(:billing_locked_user, plan: "pro", billed_on: GitHub::Billing.today - 1.day)

        assert user.billed_on

        change = create(:billing_pending_plan_change, user: user, plan: GitHub::Plan.free)
        change.run

        assert_nil user.billed_on
      end
    end

  end

  test "instruments #create and #run for org" do
    events = subscribe("pending_plan_change.create")

    org = create :credit_card_org,
      plan_duration: "month",
      plan: "business_plus",
      seats: 5
    actor = create :user
    active_on = 1.month.from_now.to_date
    pending_plan_change = org.pending_plan_changes.create!(
      plan_duration: "year",
      plan: "business",
      seats: 10,
      active_on: active_on,
      actor: actor,
    )

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: active_on,
      actor_id: actor.id,
      actor: actor.login,
      org_id: org.id,
      org: org.login,
      plan_was: GitHub::Plan.business_plus.display_name,
      plan: "team",
      plan_duration_was: "month",
      plan_duration: "year",
      seats_was: 5,
      seats: 10,
    }
    assert_equal expected_payload, event.payload

    events = subscribe("pending_plan_change.run")
    update_events = subscribe("pending_plan_change.update")
    pending_plan_change.run

    assert event = events.pop, "expected an audit log event"

    refute update_events.try(:first) # Does not audit update on run
    expected_payload = {
      active_on: GitHub::Billing.today,
      org_id: org.id,
      org: org.login,
      plan: "team",
      plan_duration: "year",
      seats: 10,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments #create and #run for business" do
    events = subscribe("pending_plan_change.create")

    business = create :business, :with_self_serve_payment
    actor = business.owners.first
    active_on = 1.month.from_now.to_date
    pending_plan_change = business.pending_plan_changes.create!(
      plan_duration: User::BillingDependency::MONTHLY_PLAN,
      active_on: active_on,
      actor: actor
    )

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: active_on,
      actor_id: actor.id,
      actor: actor.login,
      business_id: business.id,
      business: business.slug,
      plan_duration_was: User::BillingDependency::YEARLY_PLAN,
      plan_duration: User::BillingDependency::MONTHLY_PLAN
    }
    assert_equal expected_payload, event.payload

    events = subscribe("pending_plan_change.run")
    update_events = subscribe("pending_plan_change.update")
    pending_plan_change.run

    assert event = events.pop, "expected an audit log event"

    refute update_events.try(:first) # Does not audit update on run
    expected_payload = {
      active_on: GitHub::Billing.today,
      business_id: business.id,
      business: business.slug,
      plan_duration: "month"
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments seat change on #update" do
    events = subscribe("pending_plan_change.update")
    org = create(:organization, plan: :business_plus, plan_duration: :year)
    actor = create :user
    active_on = 1.month.from_now.to_date
    change = org.pending_plan_changes.create!(
      seats: 5,
      plan: GitHub::Plan.business_plus,
      plan_duration: :month,
      active_on: active_on,
      actor: actor,
    )

    # Update seats from 5 -> 3
    change.seats = 3
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      org_id: org.id,
      org: org.login,
      seats_was: 5,
      seats: 3,
    }
    assert_equal expected_payload, event.payload

    # Cancel seats change
    change.seats = nil
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      org_id: org.id,
      org: org.login,
      seats_was: 3,
      seats: nil,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments plan change on #update" do
    events = subscribe("pending_plan_change.update")
    org = create(:organization, plan: :business_plus, plan_duration: :year)
    actor = create :user
    active_on = 1.month.from_now.to_date
    change = org.pending_plan_changes.create!(
      plan: GitHub::Plan.business_plus,
      plan_duration: :month,
      active_on: active_on,
      actor: actor,
    )

    # Update plan from business_plus -> business
    change.plan = GitHub::Plan.business
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      org_id: org.id,
      org: org.login,
      plan_was: GitHub::Plan.business_plus.display_name,
      plan: GitHub::Plan.business.display_name,
    }
    assert_equal expected_payload, event.payload

    # Cancel plan change
    change.plan = nil
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      org_id: org.id,
      org: org.login,
      plan_was: GitHub::Plan.business.display_name,
      plan: nil,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments plan change for IAP subscriptions" do
    events = subscribe("account.plan_change")

    user = create :user, plan: GitHub::Plan.pro
    subscription = create :billing_plan_subscription, :apple_iap, user: user
    change = create :billing_pending_plan_change,
      active_on: GitHub::Billing.today, plan: GitHub::Plan.free, user: user, actor: user

    change.run

    assert event = events.first, "expected an audit log event"

    expected_payload = {
      old_plan: "pro",
      plan: "free",
      old_plan_duration: "month",
      plan_duration: "month",
      old_seats: 3,
      seats: 3,
      old_data_packs: 0,
      asset_packs: 0,
      tos_sha: "0000000000000000000000000000000000000000",
      old_subscription_provider: "Apple In-App Purchase",
      user: user.login,
      user_id: user.id,
      actor: user.login,
      actor_id: user.id,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments duration change on #update for org" do
    events = subscribe("pending_plan_change.update")
    org = create(:organization, plan: :business_plus, plan_duration: :year)
    actor = create :user
    active_on = 1.month.from_now.to_date
    change = org.pending_plan_changes.create!(
      plan: GitHub::Plan.business_plus,
      plan_duration: :month,
      active_on: active_on,
      actor: actor,
    )

    # Update plan_duration from month -> year
    change.plan_duration = :year
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      org_id: org.id,
      org: org.login,
      plan_duration_was: "month",
      plan_duration: "year",
    }
    assert_equal expected_payload, event.payload

    # Cancel plan_duration change
    change.plan_duration = nil
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      org_id: org.id,
      org: org.login,
      plan_duration_was: "year",
      plan_duration: nil,
    }
    assert_equal expected_payload, event.payload
  end

  test "instruments duration change on #update for business" do
    events = subscribe("pending_plan_change.update")
    business = create :business, :with_self_serve_payment
    actor = business.owners.first
    active_on = 1.month.from_now.to_date
    change = business.pending_plan_changes.create!(
      plan_duration: User::BillingDependency::YEARLY_PLAN,
      active_on: active_on,
      actor: actor
    )

    # Update plan_duration from year -> month
    change.plan_duration = :month
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      business_id: business.id,
      business: business.slug,
      plan_duration_was: "year",
      plan_duration: "month",
    }
    assert_equal expected_payload, event.payload

    # Cancel plan_duration change
    change.plan_duration = nil
    change.save!

    assert event = events.pop, "expected an audit log event"

    expected_payload = {
      active_on: change.active_on,
      business_id: business.id,
      business: business.slug,
      plan_duration_was: "month",
      plan_duration: nil,
    }
    assert_equal expected_payload, event.payload
  end

  test "doesn't track changes for invalid scheduled changes and logs failure" do
    org = create(:organization)
    3.times { org.add_member(create(:user)) }
    change = create :billing_pending_plan_change,
      user: org,
      seats: 2,
      plan: GitHub::Plan.business_plus

    msg = "Seats must be at least the number of currently filled seats"
    runtime_error = RuntimeError.new "Invalid Billing::PendingPlanChange state for user: #{org} - #{msg}"

    Failbot.expects(:report).with runtime_error,
      {
        :app => "github-user",
        "gh.user.id" => org.id
      }

    assert_no_difference "Transaction.count" do
      change.run
    end
  end

  test "tracks duration changes" do
    org = create(:organization, plan: :business_plus, plan_duration: :year)
    change = create :billing_pending_plan_change,
      user: org,
      seats: 0,
      plan: GitHub::Plan.business_plus,
      plan_duration: :month

    assert_difference "Transaction.count", 1 do
      change.run
    end
    assert_equal "switched-to-monthly", org.transactions.last.action
  end

  test "runs restrict_public_repo_creation_plan_downgrade when downgrading from business_plus" do
    user = create :user
    org = create :credit_card_org,
      plan_duration: "month",
      plan: "business_plus",
      seats: 5
    actor = create :user
    active_on = 1.month.from_now.to_date
    org.disallow_members_can_create_public_repositories(actor: user)
    refute org.members_can_create_public_repositories?
    assert org.members_can_create_repositories?
    refute_predicate org, :members_can_create_repositories_policy?
    pending_plan_change = org.pending_plan_changes.create!(
      plan_duration: "year",
      plan: "business",
      seats: 10,
      active_on: active_on,
      actor: actor,
    )
    pending_plan_change.run
    refute org.members_can_create_public_repositories?
    refute org.members_can_create_repositories?
    refute_predicate org, :members_can_create_repositories_policy?
  end

  test "unpublish private pages after downgrading from business_plus" do
    disable_feature_flag(:pages_soft_deletion)
    GitHub.stubs(:pages_custom_domain_https_enabled?).returns(true)
    actor = create(:user)
    org = create(
      :credit_card_org,
      plan_duration: "month",
      plan: "business_plus",
      seats: 5,
    )
    repo = create(:private_repository, owner: org)
    page = create(:private_page, repository: repo, owner: repo.owner)
    refute_nil org.repositories[0].page
    active_on = 1.month.from_now.to_date
    pending_plan_change = org.pending_plan_changes.create!(
      plan_duration: "year",
      plan: "business",
      seats: 10,
      active_on: active_on,
      actor: actor,
    )

    # do pending plan change with invoking DestroyPrivatePageJob.
    perform_enqueued_jobs(only: DestroyPrivatePageJob) do
      pending_plan_change.run
    end

    # assert page has been destroyed.
    assert_nil org.repositories[0].page
  end

  test "soft-delete unpublish private pages after downgrading from business_plus" do
    enable_feature_flag(:pages_soft_deletion)
    GitHub.stubs(:pages_custom_domain_https_enabled?).returns(true)
    actor = create(:user)
    org = create(
      :credit_card_org,
      plan_duration: "month",
      plan: "business_plus",
      seats: 5,
    )
    repo = create(:private_repository, owner: org)
    page = create(:private_page, repository: repo, owner: repo.owner)
    refute_nil org.repositories[0].page
    active_on = 1.month.from_now.to_date
    pending_plan_change = org.pending_plan_changes.create!(
      plan_duration: "year",
      plan: "business",
      seats: 10,
      active_on: active_on,
      actor: actor,
    )

    now = Time.zone.now.round
    Timecop.freeze(now) do
      # do pending plan change with invoking DestroyPrivatePageJob.
      perform_enqueued_jobs(only: DestroyPrivatePageJob) do
        pending_plan_change.run
      end

      # assert page has been destroyed.
      refute_nil org.repositories[0].page
      assert_equal now.to_date, org.repositories[0].page.deleted_at.to_date
    end
  end

  test "expires GHEC Trial, don't remove the coupon, and don't downgrade to free plan" do
    org = create(:free_organization, seats: 0)
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    coupon = create(
      :coupon,
      code: "freestuff",
      plan: GitHub::Plan.business_plus,
      discount: 1.0,
      duration: 31,
      limit: 1,
      group: "sales-serve",
      expires_at: 1.year.from_now,
      note: "testing",
      staff_actor_only: false
    )

    org.redeem_coupon("freestuff", allow_reuse: true, actor: org.admins.first)

    plan_trial = Billing::PlanTrial.find_by!(
      user: org,
      plan: GitHub::Plan::BUSINESS_PLUS,
    )
    T.must(plan_trial.pending_plan_change).run

    org.reload

    assert_equal coupon, org.coupon
    assert_equal "business_plus", org.plan.name
  end

  test "expires Enterprise Cloud Trial, don't remove microsoft coupons, and don't downgrade to free plan" do
    org = create(:free_organization, seats: 0)
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    coupon = create(
      :coupon,
      code: "freecoupon",
      plan: GitHub::Plan.business_plus,
      discount: 1.0,
      duration: 31,
      limit: 1,
      group: "microsoft",
      expires_at: 1.year.from_now,
      note: "testing",
      staff_actor_only: false
    )

    org.redeem_coupon("freecoupon", allow_reuse: true, actor: org.admins.first)

    plan_trial = Billing::PlanTrial.find_by!(
      user: org,
      plan: GitHub::Plan::BUSINESS_PLUS,
    )
    T.must(plan_trial.pending_plan_change).run

    org.reload

    assert_equal coupon, org.coupon
    assert_equal "business_plus", org.plan.name
  end

  test "expires Enterprise Cloud Trial, don't remove startup-program coupons, and don't downgrade to free plan" do
    org = create(:free_organization, seats: 0)
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    coupon = create(
      :coupon,
      code: "freecoupon",
      plan: GitHub::Plan.business_plus,
      discount: 1.0,
      duration: 31,
      limit: 1,
      group: "startup-program",
      expires_at: 1.year.from_now,
      note: "testing",
      staff_actor_only: false
    )

    org.redeem_coupon("freecoupon", allow_reuse: true, actor: org.admins.first)

    plan_trial = Billing::PlanTrial.find_by!(
      user: org,
      plan: GitHub::Plan::BUSINESS_PLUS,
    )
    T.must(plan_trial.pending_plan_change).run

    org.reload

    assert_equal coupon, org.coupon
    assert_equal "business_plus", org.plan.name
  end

  context "#cancel" do
    test "sets it as complete and updates the active_on date" do
      change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 1.month)

      change.cancel

      assert change.is_complete?
      assert_equal GitHub::Billing.today, change.active_on
    end
  end

  context "#cancel_pending_subscription_item_changes!" do
    test "cancels all pending subscription item changes" do
      copilot_product_uuid = create :billing_product_uuid, :copilot
      change = create(:billing_pending_plan_change, active_on: GitHub::Billing.today + 1.month)
      create :billing_pending_subscription_item_change, :cancellation, subscribable: copilot_product_uuid, pending_plan_change: change
      assert change.pending_subscription_item_changes.any?

      change.cancel_pending_subscription_item_changes!

      change.reload
      assert change.pending_subscription_item_changes.empty?
    end
  end

  test "instruments downgrade seats change for business" do
    events = subscribe("account.plan_change")

    business = create :business, :with_self_serve_payment, seats: 40
    actor = business.owners.first
    active_on = 1.month.from_now.to_date
    pending_plan_change = business.pending_plan_changes.create!(
      plan_duration: nil,
      active_on: active_on,
      actor: actor,
      seats: 30,
    )

    expected_payload = {
      plan: :business_plus,
      old_plan: :business_plus,
      old_plan_duration: "year",
      plan_duration: "year",
      business_id: business.id,
      business: business.slug,
      old_seats: 40,
      seats: 30,
    }

    pending_plan_change.run
    assert event = events.pop, "expected an audit log event"
    assert_equal expected_payload, event.payload
  end
end if GitHub.billing_enabled?
