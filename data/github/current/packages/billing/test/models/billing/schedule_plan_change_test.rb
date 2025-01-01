# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingSchedulePlanChangeTest < GitHub::TestCase
  fixtures do
    @business = create :business, :with_self_serve_payment
    @plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business.customer
    @business_admin = @business.owners.first
    @org = create :organization, business: @business, admin: @business_admin
  end

  context "#run" do
    test "maintains free trial status when modifying an existing free trial subscription item change" do
      freeze_time do
        item = create(:billing_subscription_item, :with_product_uuid)
        user = item.account
        effective_on = 5.days.from_now

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SchedulePlanChange.run \
            account: user,
            actor: user,
            subscribable: item.subscribable,
            subscribable_quantity: 1,
            free_trial: true,
            active_on: effective_on,
            plan_subscription: user.plan_subscription
        end

        # Assertions to ensure proper initial state
        assert_equal 1, user.pending_subscription_item_changes.count
        change = user.pending_subscription_item_changes.first
        assert change.free_trial

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          # Schedule a cancellation after the trial ends
          Billing::SchedulePlanChange.run \
            account: user,
            actor: user,
            subscribable: item.subscribable,
            subscribable_quantity: 0,
            free_trial: false,
            active_on: effective_on,
            plan_subscription: user.plan_subscription
        end

        assert_equal 1, user.pending_subscription_item_changes.count
        change = user.pending_subscription_item_changes.first
        assert change.free_trial
        assert_equal 0, change.quantity
      end
    end

    context "self-serve payment enterprise account orgs marketplace apps" do
      test "maintains free trial status when modifying an existing free trial subscription item change" do
        freeze_time do
          item = create :billing_subscription_item, organization: @org
          effective_on = 5.days.from_now

          assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
            Billing::SchedulePlanChange.run \
              account: @business,
              actor: @business_admin,
              subscribable: item.subscribable,
              subscribable_quantity: 1,
              free_trial: true,
              active_on: effective_on,
              plan_subscription: @plan_subscription,
              organization: @org
          end

          # Assertions to ensure proper initial state
          assert_equal 1, @business.pending_subscription_item_changes.count
          change = @business.pending_subscription_item_changes.first
          assert change.free_trial

          assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
            # Schedule a cancellation after the trial ends
            Billing::SchedulePlanChange.run \
              account: @business,
              actor: @business_admin,
              subscribable: item.subscribable,
              subscribable_quantity: 0,
              free_trial: false,
              active_on: effective_on,
              plan_subscription: @plan_subscription,
              organization: @org
          end

          assert_equal 1, @business.pending_subscription_item_changes.count
          assert_equal @org.id, change.organization_id
          change = @business.pending_subscription_item_changes.first
          assert change.free_trial
          assert_equal 0, change.quantity
        end
      end
    end
  end

  context "schedule plan change for organization" do
    test "creates a plan change" do
      org = create :organization, \
        billed_on: GitHub::Billing.today,
        plan_duration: "year",
        plan: "free",
        seats: 10

      assert_difference "Billing::PendingPlanChange.count", 1 do
        result = Billing::SchedulePlanChange.run \
          account: org,
          actor: org,
          seats: 4,
          plan: GitHub::Plan.find("silver"),
          plan_duration: "month",
          data_packs: 2

        assert result.success?
      end

      change = org.pending_plan_changes.last
      assert_equal GitHub::Plan.silver, change.plan
      assert_equal "month", change.plan_duration
      assert_equal 4, change.seats
      assert_equal 2, change.data_packs
      assert_equal org.next_billing_date, change.active_on
    end

    test "queues a plan change job" do
      org = create :organization, plan: "free", seats: 10, billed_on: GitHub::Billing.today

      Billing::SchedulePlanChange.run \
        account: org,
        actor: org,
        seats: 4,
        plan: GitHub::Plan.find("silver"),
        plan_duration: "month"

      offset_seconds = (T.must(T.must(Billing::PendingPlanChange.last).id) % 60).seconds
      scheduled_at = org.next_billing_date.to_datetime + offset_seconds

      Billing::PendingPlanChange.any_instance.stubs(:run).returns(true)
      perform_enqueued_jobs(only: [RunPendingPlanChangeJob])

      assert_performed_with(job: RunPendingPlanChangeJob, at: scheduled_at)
    end

    test "updates incomplete pending change" do
      org = create :organization, plan: "free", seats: 10, billed_on: GitHub::Billing.today
      change = org.pending_plan_changes.create \
        active_on: GitHub::Billing.today,
        plan: "pro",
        seats: 5

      Billing::SchedulePlanChange.run \
        account: org,
        actor: org,
        seats: 4,
        plan: GitHub::Plan.find("silver"),
        plan_duration: "month"

      assert_equal 4, change.reload.seats
      assert_equal GitHub::Plan.silver, change.reload.plan
    end

    test "does not assign seats below base units for an incomplete plan change" do
      org = create :credit_card_org, plan: "business_plus", seats: 10, billed_on: GitHub::Billing.today
      new_plan = GitHub::Plan.business

      change = org.pending_plan_changes.create \
        active_on: GitHub::Billing.today,
        plan: new_plan.to_s,
        seats: nil

      Billing::SchedulePlanChange.run \
        account: org,
        actor: org,
        seats: new_plan.base_units - 1

      assert_equal new_plan.base_units, change.reload.seats

      change.update!(seats: 7)
      Billing::SchedulePlanChange.run \
        account: org,
        actor: org,
        seats: new_plan.base_units - 1

      assert_equal 1, change.reload.seats
    end

    test "schedules the job for the active_on date" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 5, 15)) do
        org = create :organization, \
          plan_duration: "year",
          plan: "free",
          seats: 10

        assert_difference "Billing::PendingPlanChange.count", 1 do
          result = Billing::SchedulePlanChange.run \
            account: org,
            actor: org,
            active_on: GitHub::Billing.today + 1.month,
            seats: 4,
            plan: GitHub::Plan.find("silver"),
            plan_duration: "month",
            data_packs: 2

          assert result.success?
        end

        change = org.pending_plan_changes.last
        assert_equal GitHub::Billing.today + 1.month, change.active_on
      end
    end

    test "schedules the job for a specific time of day" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 8, 5)) do
        org = create :organization, plan: "free", seats: 10, billed_on: GitHub::Billing.today
        schedule_at = Time.zone.now + 30.minutes

        Billing::SchedulePlanChange.run \
          account: org,
          actor: org,
          seats: 4,
          plan: GitHub::Plan.find("silver"),
          plan_duration: "month",
          schedule_at: schedule_at

        Billing::PendingPlanChange.any_instance.stubs(:run).returns(true)
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])

        assert_performed_with(job: RunPendingPlanChangeJob, at: schedule_at)
      end
    end

    test "returns error message for invalid seat count" do
      org = create :organization, plan: "free", seats: 10, billed_on: GitHub::Billing.today
      result = Billing::SchedulePlanChange.run \
        account: org,
        actor: org,
        seats: -1,
        plan: GitHub::Plan.business,
        plan_duration: "month"

      refute result.success?
      assert_match(/Seats must be at least/, result.error)
    end

    test "doesn't override account settings" do
      org = create :organization, plan: "free", seats: 10, billed_on: GitHub::Billing.today
      Billing::SchedulePlanChange.run \
        account: org,
        actor: org,
        seats: 4,
        plan: GitHub::Plan.find("silver"),
        plan_duration: "year"

      assert_equal 10, org.seats
      assert_equal GitHub::Plan.free, org.plan
      assert_equal "month", org.plan_duration
    end

    test "schedules a cancellation for an mp item" do
      travel_to("2022-09-19") do
        item = create :billing_subscription_item
        user = item.account

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SchedulePlanChange.run \
            account: user,
            actor: user,
            subscribable: item.subscribable,
            subscribable_quantity: 0
        end

        change = user.pending_cycle_change.pending_subscription_item_changes.last
        assert_equal 0, change.quantity
        assert_equal item.subscribable, change.subscribable
        assert_equal user.next_billing_date, change.active_on
      end
    end

    test "schedules a cancellation for a sponsorship item" do
      travel_to("2022-09-19") do
        item = create :sponsors_subscription_item
        user = item.account
        user.update_columns(billed_on: GitHub::Billing.today + 5.days)

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SchedulePlanChange.run \
            account: user,
            actor: user,
            subscribable: item.subscribable,
            subscribable_quantity: 0,
            plan_subscription: item.plan_subscription
        end

        change = user.pending_cycle_change.pending_subscription_item_changes.last
        assert_equal 0, change.quantity
        assert_equal item.subscribable, change.subscribable
        assert_equal user.next_billing_date, change.active_on
      end
    end

    test "schedules a cancellation for a sponsorship item on a sponsors-purpose plan subscription" do
      skip unless GitHub.sponsors_enabled?

      travel_to("2022-09-19") do
        org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        org.sponsors_customer.update_columns(bill_cycle_day: 25)

        refute_equal org.next_billing_date, org.next_sponsors_billing_date, "invoiced org should have different billing dates"

        item = create(:sponsors_subscription_item,
          plan_subscription: org.sponsors_plan_subscription,
        )

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SchedulePlanChange.run \
            account: org,
            actor: org.admin,
            subscribable: item.subscribable,
            subscribable_quantity: 0,
            plan_subscription: org.sponsors_plan_subscription
        end

        change = org.pending_cycle_change.pending_subscription_item_changes.last
        assert_equal 0, change.quantity
        assert_equal item.subscribable, change.subscribable
        assert_equal org.next_sponsors_billing_date, change.active_on
      end
    end

    test "schedules a plan change for an mp item" do
      item = create :billing_subscription_item
      user = item.account
      plan = item.subscribable
      listing = plan.listing
      plan_two = create :marketplace_listing_plan, listing: listing

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SchedulePlanChange.run \
          account: user,
          actor: user,
          subscribable: plan_two,
          subscribable_quantity: 3
      end

      change = user.pending_cycle_change.pending_subscription_item_changes.last
      assert_equal 3, change.quantity
      assert_equal plan_two, change.subscribable
    end

    test "schedules a plan change for an sponsorship item" do
      item = create :sponsors_subscription_item
      user = item.account
      tier_one = item.subscribable
      listing = tier_one.listing
      tier_two = create(:sponsors_tier, sponsors_listing: listing)

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SchedulePlanChange.run \
          account: user,
          actor: user,
          subscribable: tier_two,
          subscribable_quantity: 1,
          plan_subscription: item.plan_subscription
      end

      change = user.pending_cycle_change.pending_subscription_item_changes.last
      assert_equal 1, change.quantity
      assert_equal tier_two, change.subscribable
    end

    test "updates existing pending change for a mp listing" do
      item = create :billing_subscription_item, quantity: 10
      user = item.account
      plan = item.subscribable
      listing = plan.listing
      plan_two = create :marketplace_listing_plan, listing: listing

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SchedulePlanChange.run \
          account: user,
          actor: user,
          subscribable: plan,
          subscribable_quantity: 4
      end

      assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
        Billing::SchedulePlanChange.run \
          account: user,
          actor: user,
          subscribable: plan_two,
          subscribable_quantity: 6
      end

      change = user.pending_cycle_change.pending_subscription_item_changes.last
      assert_equal 6, change.quantity
      assert_equal plan_two, change.subscribable
    end

    test "updates existing pending change for a sponsorship listing" do
      item = create :sponsors_subscription_item
      user = item.account
      tier_one = item.subscribable
      listing = tier_one.listing
      tier_two = create(:sponsors_tier, sponsors_listing: listing)
      tier_three = create(:sponsors_tier, sponsors_listing: listing)

      assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::SchedulePlanChange.run \
          account: user,
          actor: user,
          subscribable: tier_two,
          subscribable_quantity: 1,
          plan_subscription: item.plan_subscription
      end

      assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
        Billing::SchedulePlanChange.run \
          account: user,
          actor: user,
          subscribable: tier_three,
          subscribable_quantity: 1,
          plan_subscription: item.plan_subscription
      end

      change = user.pending_cycle_change.pending_subscription_item_changes.last
      assert_equal 1, change.quantity
      assert_equal tier_three, change.subscribable
    end

    test "doesn't override data packs" do
      change = create :billing_pending_plan_change, data_packs: 5

      result = Billing::SchedulePlanChange.run \
        account: change.user,
        actor: change.user

      assert result.success?
      assert_equal 5, change.reload.data_packs
    end

    test "doesn't override pending plan changes" do
      user = create :organization, plan: "free", seats: 7, plan_duration: "month"
      change = create :billing_pending_plan_change,
        user: user,
        plan: "business",
        seats: 5,
        plan_duration: "year"

      Billing::SchedulePlanChange.run \
        account: user,
        actor: user

      assert_equal GitHub::Plan.business, change.reload.plan
      assert_equal 5, change.reload.seats
      assert_equal "year", change.reload.plan_duration

      Billing::SchedulePlanChange.run \
        account: user,
        actor: user,
        plan: user.plan,
        seats: user.seats,
        plan_duration: user.plan_duration

      assert_equal GitHub::Plan.business, change.reload.plan
      assert_equal 5, change.reload.seats
      assert_equal "year", change.reload.plan_duration
    end

    test "schedules separate pending plan changes when they are active on different days" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 15)) do
        user = create :organization, plan: "business", seats: 7, plan_duration: "month"
        downgrade = create :billing_pending_plan_change,
          user: user,
          plan: "business",
          seats: 5,
          plan_duration: "month"

        Billing::SchedulePlanChange.run \
          account: user,
          actor: user

        assert_equal GitHub::Plan.business, downgrade.reload.plan
        assert_equal 5, downgrade.reload.seats

        plan = create :marketplace_listing_plan, :published,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true
        plan_subscription = create :billing_plan_subscription, user: user
        item = create :billing_subscription_item, subscribable: plan, plan_subscription: plan_subscription

        Billing::SchedulePlanChange.run \
            account: user,
            actor: user,
            active_on: 1.week.from_now,
            free_trial: true,
            subscribable: plan,
            subscribable_quantity: item.quantity

        free_trial_change = user.pending_free_trial_changes.last

        assert_equal 2, user.pending_plan_changes.count
        assert_equal user.next_billing_date, downgrade.active_on
        assert_equal GitHub::Billing.today + 1.week, free_trial_change.active_on
        assert free_trial_change.pending_subscription_item_changes.free_trial.any?
      end
    end

    test "always creates a seperate change for free trials" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 15)) do
        user = create :organization, plan: "business", seats: 7, plan_duration: "month"
        downgrade = create :billing_pending_plan_change,
          user: user,
          plan: "business",
          seats: 5,
          plan_duration: "month"

        Billing::SchedulePlanChange.run \
          account: user,
          actor: user

        assert_equal GitHub::Plan.business, downgrade.reload.plan
        assert_equal 5, downgrade.reload.seats

        plan = create :marketplace_listing_plan, :published,
          monthly_price_in_cents: 5_00,
          yearly_price_in_cents: 60_00,
          has_free_trial: true
        plan_subscription = create :billing_plan_subscription, user: user
        item = create :billing_subscription_item, subscribable: plan, plan_subscription: plan_subscription

        Billing::SchedulePlanChange.run \
            account: user,
            actor: user,
            active_on: downgrade.active_on,
            subscribable: plan,
            free_trial: true,
            subscribable_quantity: item.quantity

        change = user.reload.pending_plan_changes.last

        assert_equal 2, user.pending_plan_changes.count
        assert_equal user.next_billing_date, downgrade.active_on
        assert_equal 1, change.pending_subscription_item_changes.count
      end
    end

    test "schedule plan change for a product uuid subscription item to downgrade quantity" do
      product_uuid = create(:billing_product_uuid, name: "Test product")
      plan_subscription = create(:billing_plan_subscription, :org)
      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: product_uuid, quantity: 5)
      organization = plan_subscription.user
      actor = organization.owner
      new_seat_quantity = 1

      Billing::SchedulePlanChange.run(
        account: organization,
        actor: actor,
        subscribable: product_uuid,
        subscribable_quantity: new_seat_quantity,
        plan_subscription: plan_subscription
      )

      organization.reload
      pending_subscription_item_change = organization.pending_plan_changes.sole.pending_subscription_item_changes.sole

      assert_equal new_seat_quantity, pending_subscription_item_change.quantity
      assert_equal product_uuid.id, pending_subscription_item_change.subscribable_id
    end

    test "schedule plan change fails for a product uuid subscription item with an invalid quantity" do
      product_uuid = create(:billing_product_uuid, name: "Test product")
      plan_subscription = create(:billing_plan_subscription, :org)
      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: product_uuid, quantity: 5)
      organization = plan_subscription.user
      actor = organization.owner
      invalid_seat_quantity = -1

      result = Billing::SchedulePlanChange.run(
        account: organization,
        actor: actor,
        subscribable: product_uuid,
        subscribable_quantity: invalid_seat_quantity,
        plan_subscription: plan_subscription
      )

      organization.reload

      assert result.failed?
      assert_equal 5, organization.active_subscription_items.sole.quantity
      assert_equal [], organization.pending_plan_changes
    end

    context "self-serve payment enterprise account orgs" do
      test "schedules a cancellation for an mp item" do
        travel_to("2022-09-19") do
          item = create :billing_subscription_item, organization: @org

          assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
            Billing::SchedulePlanChange.run \
              account: @business,
              actor: @business_admin,
              subscribable: item.subscribable,
              subscribable_quantity: 0,
              organization: @org
          end

          change = @business.pending_cycle_change.pending_subscription_item_changes.last
          assert_equal @org.id, change.organization_id
          assert_equal 0, change.quantity
          assert_equal item.subscribable, change.subscribable
          assert_equal @business.next_billing_date, change.active_on
        end
      end

      test "schedules a plan change for an mp item" do
        item = create :billing_subscription_item, organization: @org
        plan = item.subscribable
        listing = plan.listing
        plan_two = create :marketplace_listing_plan, listing: listing

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SchedulePlanChange.run \
            account: @business,
            actor: @business_admin,
            subscribable: plan_two,
            subscribable_quantity: 3,
            organization: @org
        end

        change = @business.pending_cycle_change.pending_subscription_item_changes.last
        assert_equal @org.id, change.organization_id
        assert_equal 3, change.quantity
        assert_equal plan_two, change.subscribable
      end

      test "updates existing pending change for a mp listing" do
        item = create :billing_subscription_item, organization: @org
        plan = item.subscribable
        listing = plan.listing
        plan_two = create :marketplace_listing_plan, listing: listing

        assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
          Billing::SchedulePlanChange.run \
            account: @business,
            actor: @business_admin,
            subscribable: plan,
            subscribable_quantity: 4,
            organization: @org
        end

        assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
          Billing::SchedulePlanChange.run \
            account: @business,
            actor: @business_admin,
            subscribable: plan_two,
            subscribable_quantity: 6,
            organization: @org
        end

        change = @business.pending_cycle_change.pending_subscription_item_changes.last
        assert_equal @org.id, change.organization_id
        assert_equal 6, change.quantity
        assert_equal plan_two, change.subscribable
      end
    end
  end

  context "schedule plan change for business" do
    test "creates a plan change" do
      business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
      actor = business.owners.first

      assert_difference "Billing::PendingPlanChange.count", 1 do
        result = Billing::SchedulePlanChange.run(
          account: business,
          actor: actor,
          seats: 100,
          plan_duration: "month"
        )
        assert result.success?
      end

      change = business.pending_plan_changes.last
      assert_equal "month", change.plan_duration
      assert_equal business.next_billing_date, change.active_on
    end

    test "queues a plan change job" do
      business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
      actor = business.owners.first
      Billing::SchedulePlanChange.run(
        account: business,
        actor: actor,
        seats: 100,
        plan_duration: "month"
      )

      offset_seconds = (T.must(T.must(Billing::PendingPlanChange.last).id) % 60).seconds
      scheduled_at = business.next_billing_date.to_datetime + offset_seconds

      Billing::PendingPlanChange.any_instance.stubs(:run).returns(true)
      perform_enqueued_jobs(only: [RunPendingPlanChangeJob])

      assert_performed_with(job: RunPendingPlanChangeJob, at: scheduled_at)
    end

    test "updates incomplete pending change" do
      business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
      actor = business.owners.first
      change = business.pending_plan_changes.create(
        plan_duration: "year",
        active_on: GitHub::Billing.today,
        actor: actor
      )

      Billing::SchedulePlanChange.run(
        account: business,
        actor: actor,
        seats: 100,
        plan_duration: "month"
      )
      change.reload

      assert_equal "month", change.plan_duration
    end

    test "schedules the job for the active_on date" do
      Timecop.freeze(GitHub::Billing.timezone.local(2017, 5, 15)) do
        business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
        actor = business.owners.first

        assert_difference "Billing::PendingPlanChange.count", 1 do
          result = Billing::SchedulePlanChange.run(
            account: business,
            actor: actor,
            active_on: GitHub::Billing.today + 1.month,
            seats: 100,
            plan_duration: "month"
          )

          assert result.success?
        end

        change = business.pending_plan_changes.last
        assert_equal GitHub::Billing.today + 1.month, change.active_on
      end
    end

    test "schedules the job for a specific time of day" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 8, 5)) do
        business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
        actor = business.owners.first
        schedule_at = Time.zone.now + 30.minutes

        Billing::SchedulePlanChange.run(
          account: business,
          actor: actor,
          seats: 100,
          plan_duration: "month",
          schedule_at: schedule_at
        )

        Billing::PendingPlanChange.any_instance.stubs(:run).returns(true)
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])

        assert_performed_with(job: RunPendingPlanChangeJob, at: schedule_at)
      end
    end

    test "doesn't override account settings" do
      business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
      actor = business.owners.first

      assert_equal "year", business.plan_duration
      assert_equal 100, business.seats

      Billing::SchedulePlanChange.run(
        account: business,
        actor: actor,
        seats: 150,
        plan_duration: "month"
      )
      business.reload

      assert_equal 100, business.seats
      assert_equal "year", business.plan_duration
    end

    test "doesn't override pending plan changes" do
      business = create :business, :with_self_serve_payment, billing_term_ends_at: GitHub::Billing.today - 1.day
      actor = business.owners.first

      assert_equal "year", business.plan_duration
      assert_equal 100, business.seats

      change = create :billing_pending_plan_change, customer: business.customer, seats: 150, plan_duration: "month"
      Billing::SchedulePlanChange.run account: business, actor: actor
      change.reload

      assert_equal 150, change.seats
      assert_equal "month", change.plan_duration

      Billing::SchedulePlanChange.run(
        account: business,
        actor: actor,
        seats: business.seats,
        plan_duration: business.plan_duration
      )
      change.reload

      assert_equal 150, change.seats
      assert_equal "month", change.plan_duration
    end

    test "re-uses pending plan change if a new change is expected to run on the same date" do
      next_billing_date = 1.month.from_now
      business = create(:business, customer: create(:customer, :zuora, :self_serve, billing_end_date: next_billing_date - 1.day))

      change = create :billing_pending_plan_change,
        :business,
        active_on: next_billing_date,
        customer: business.customer,
        seats: 150,
        plan_duration: "month"

      assert_equal 1, business.pending_plan_changes.count
      assert_equal 0, business.pending_plan_changes.sole.pending_subscription_item_changes.count

      advanced_security = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, user: nil, customer: business.customer)
      subscription_item = create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: advanced_security)

      Billing::SchedulePlanChange.run \
        account: business,
        actor: business.owners.first,
        active_on: change.active_on,
        plan_subscription: plan_subscription,
        subscribable: advanced_security,
        subscribable_quantity: 1

      assert_equal 1, business.reload.pending_plan_changes.count
      assert_equal 1, business.pending_plan_changes.sole.pending_subscription_item_changes.count
      assert_equal subscription_item.pending_subscription_item_change.pending_plan_change.id, change.id
      assert_equal business.next_billing_date, change.active_on
    end

    test "schedule plan change for a product uuid subscription item to downgrade quantity" do
      product_uuid = create(:billing_product_uuid, name: "Test product")
      plan_subscription = create(:billing_plan_subscription, :business_owned)
      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: product_uuid, quantity: 5)
      business = plan_subscription.business
      actor = business.owners.first
      new_seat_quantity = 1

      Billing::SchedulePlanChange.run(
        account: business,
        actor: actor,
        subscribable: product_uuid,
        subscribable_quantity: new_seat_quantity,
        plan_subscription: plan_subscription
      )

      business.reload
      pending_subscription_item_change = business.pending_plan_changes.sole.pending_subscription_item_changes.sole

      assert_equal new_seat_quantity, pending_subscription_item_change.quantity
      assert_equal product_uuid.id, pending_subscription_item_change.subscribable_id
    end

    test "schedule plan change fails for a product uuid subscription item with an invalid quantity" do
      product_uuid = create(:billing_product_uuid, name: "Test product")
      plan_subscription = create(:billing_plan_subscription, :business_owned)
      create(:billing_subscription_item, :paid, plan_subscription: plan_subscription, subscribable: product_uuid, quantity: 5)
      business = plan_subscription.business
      actor = business.owners.first
      invalid_seat_quantity = -1

      result = Billing::SchedulePlanChange.run(
        account: business,
        actor: actor,
        subscribable: product_uuid,
        subscribable_quantity: invalid_seat_quantity,
        plan_subscription: plan_subscription
      )

      business.reload

      assert result.failed?
      assert_equal 5, business.active_subscription_items.sole.quantity
      assert_equal [], business.pending_plan_changes
    end
  end
end if GitHub.billing_enabled?
