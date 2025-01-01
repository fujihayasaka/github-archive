# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PlanChange::PerSeatPricingModelTest < GitHub::BillingTestCase
  include HydroTestHelpers
  include GitHub::ZuoraTestHelper

  fixtures do
    @actor = create(:user)
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  context "hydro", skip_enterprise: true do
    test "does not log trial plan change if trial is expired past message duration" do
      org = create :credit_card_org, plan: "free", seats: 6
      Billing::EnterpriseCloudTrial.new(org).create
      plan_change = Billing::PendingPlanChange.last
      T.must(plan_change).update(active_on: 100.days.ago)
      T.must(plan_change).run

      reset_hydro

      change = Billing::PlanChange::PerSeatPricingModel.new(org.reload, new_plan: :business, seats: 50)
      change.switch(actor: org.admins.first)

      refute_hydro_messages(schema: "github.billing.v0.TrialPlanChange")
    end

    test "logs trial plan change with correct expired status when expired" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "free", seats: 6
      Billing::EnterpriseCloudTrial.new(org).create
      T.must(Billing::PendingPlanChange.last).run

      reset_hydro

      change = Billing::PlanChange::PerSeatPricingModel.new(org.reload, new_plan: :business, seats: 50)
      change.switch(actor: org.admins.first)

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(org),
        trial_plan: "business_plus",
        new_plan: "business",
        trial_expired: true,
        user_initiated: true,
      }, schema: "github.billing.v0.TrialPlanChange")
    end

    test "logs trial plan change event when a plan trial is present" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "free", seats: 6
      Billing::EnterpriseCloudTrial.new(org).create

      reset_hydro

      change = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: :business_plus)
      change.switch(actor: org.admins.first)

      assert_hydro_published({
        account: Hydro::EntitySerializer.user(org),
        trial_plan: "business_plus",
        new_plan: "business_plus",
        trial_expired: false,
        user_initiated: true,
      }, schema: "github.billing.v0.TrialPlanChange")
    end
  end

  def build_pricing_model(organization: nil, old_plan: "bronze", old_plan_duration: "year", seats: nil, plan_duration: nil, old_coupon: nil, coupon: nil, new_plan: nil)
    org = organization || create(:credit_card_org,
            :with_valid_contact_for_billing,
            plan: old_plan,
            plan_duration: old_plan_duration,
            billed_on: GitHub::Billing.today + 10.days)
    org.add_admin(create(:user))
    org.redeem_coupon(old_coupon) if old_coupon
    Billing::PlanChange::PerSeatPricingModel.new(org, seats: seats, plan_duration: plan_duration, coupon: coupon, new_plan: new_plan)
  end

  def percent_service_remaining(pricing_model)
    pricing_model.old_subscription.service_percent_remaining
  end

  def percent_new_service_remaining(pricing_model)
    pricing_model.new_subscription.service_percent_remaining
  end

  def today
    GitHub::Billing.today
  end

  context "#base_seats" do
    test "returns the new plan's base units" do
      pricing_model = build_pricing_model

      assert_equal pricing_model.new_plan.base_units, pricing_model.base_seats
    end
  end

  test "test that initial seats using the plans base units" do
    org           = create :credit_card_org
    pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business_plus)

    assert_equal 1, pricing_model.seats
  end

  test "prices are duration aware" do
    GitHub.flipper[:remove_org_annual_discount].enable

    org = create :credit_card_org
    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org, \
      new_plan: GitHub::Plan.business,
      seats: 10,
      plan_duration: 12

    assert_money 48 * 9 * 100, pricing_model.additional_seats_price
    assert_money 48 * 100,     pricing_model.unit_price
    assert_money 48 * 100,    pricing_model.base_price
  end

  context "price calculations" do
    test "free to per seat monthly" do
      org = create :credit_card_org, plan: "free"
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 10, plan_duration: "month")

      assert_money 0, pricing_model.price_of_remaining_service
      assert_money 4_00 + 4_00 * 9, pricing_model.renewal_price
      assert_money 4_00 + 4_00 * 9, pricing_model.final_price
    end

    test "monthly silver to per seat monthly" do
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 4, 14, 8, 0, 0)) do
        pricing_model = build_pricing_model(old_plan: "silver", old_plan_duration: "month", seats: 10, plan_duration: "month")
        percent_service_remaining = percent_service_remaining(pricing_model)
        refute pricing_model.starting_new_subscription?

        assert_money (50_00 * percent_service_remaining).to_i, pricing_model.price_of_remaining_service
        assert_money 4_00 + 4_00 * 9, pricing_model.renewal_price
        assert_money -290, pricing_model.final_price
      end
    end

    test "monthly silver to per seat yearly" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(false)
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 4, 14, 8, 0, 0)) do
        pricing_model = build_pricing_model(old_plan: "silver", old_plan_duration: "month", seats: 10, plan_duration: "year")
        percent_service_remaining = percent_service_remaining(pricing_model)
        assert pricing_model.starting_new_subscription?

        assert_money (50_00 * percent_service_remaining).to_i, pricing_model.price_of_remaining_service
        assert_money 48_00 + 48_00 * 9, pricing_model.renewal_price
        assert_money 48_00 + 48_00 * 9, pricing_model.final_price
      end
    end

    test "monthly silver to per seat yearly with coupon" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(false)
      Timecop.freeze(GitHub::Billing.timezone.local(2020, 4, 14, 8, 0, 0)) do
        coupon = create :coupon, duration: 90, discount: 30
        pricing_model = build_pricing_model(old_plan: "silver", old_plan_duration: "month", seats: 10, plan_duration: "year", old_coupon: coupon)
        assert pricing_model.starting_new_subscription?
        # ($50 old plan cost * 9 / 31.0) - $30 coupon < $0
        assert_money 0_00, pricing_model.price_of_remaining_service
        assert_money 48_00 - 30_00 * 12 + 48_00 * 9, pricing_model.renewal_price
        assert_money 48_00 - 30_00 * 12 + 48_00 * 9, pricing_model.final_price
      end
    end

    test "yearly silver to per seat monthly" do
      pricing_model = build_pricing_model(old_plan: "silver", seats: 10, plan_duration: "month")
      percent_service_remaining = percent_service_remaining(pricing_model)
      assert pricing_model.starting_new_subscription?
      assert_money 12 * 50_00 * percent_service_remaining, pricing_model.price_of_remaining_service
      assert_money 4_00 + 4_00 * 9, pricing_model.renewal_price
      assert_money 4_00 + 4_00 * 9, pricing_model.final_price
    end

    test "yearly silver to per seat yearly" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(false)
      # Avoid leap days since we assume 365 days in a year in our assertion for `#final_price`
      travel_to GitHub::Billing.timezone.local(2021, 4, 14, 12, 0, 0) do
        pricing_model = build_pricing_model(old_plan: "silver", seats: 10)
        percent_service_remaining = percent_service_remaining(pricing_model)
        refute pricing_model.starting_new_subscription?

        assert_money 12 * 50_00 * percent_service_remaining, pricing_model.price_of_remaining_service
        assert_money 48_00 + 48_00 * 9, pricing_model.renewal_price
        assert_money -296, pricing_model.final_price
        assert_money 4800, pricing_model.unit_price

      end
    end

    test "yearly free to business with discount" do
      Organization.any_instance.stubs(:annual_discount_allowed?).returns(true)
      # Avoid leap days since we assume 365 days in a year in our assertion for `#final_price`
      travel_to GitHub::Billing.timezone.local(2021, 4, 14, 12, 0, 0) do
        pricing_model = build_pricing_model(old_plan: "free", new_plan: "business", seats: 10)
        percent_service_remaining = percent_service_remaining(pricing_model)

        assert pricing_model.starting_new_subscription?
        assert_money 44_00 + 44_00 * 9, pricing_model.renewal_price
        assert_money 44_000, pricing_model.final_price
        assert_money 4400, pricing_model.unit_price

      end
    end
  end

  context "with a spammy user" do
    test "cannot switch to upgraded plan" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business_plus)
      @actor.mark_as_spammy

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is flagged and unable to make purchases/, pricing_model.error_messages.join
    end

    test "cannot switch from legacy to higher legacy tier" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "silver"
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.gold)
      @actor.mark_as_spammy

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is flagged and unable to make purchases/, pricing_model.error_messages.join
    end

    test "cannot switch from legacy to per seat even if it is a downgrade in price" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "gold"
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business)
      @actor.mark_as_spammy

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is flagged and unable to make purchases/, pricing_model.error_messages.join
    end

    test "can switch to downgraded plan" do
      org = create :credit_card_org, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.free)
      @actor.mark_as_spammy

      pricing_model.switch(actor: @actor)

      Timecop.travel(GitHub::Billing.date_in_timezone(org.reload.next_billing_date)) do
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
      end

      assert pricing_model.organization.valid?
      assert org.reload.plan.free?
    end
  end

  context "with a spammy organization" do
    test "cannot switch to upgraded plan" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business_plus)
      org.mark_as_spammy

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is flagged and unable to make purchases/, pricing_model.error_messages.join
    end

    test "cannot switch from legacy to higher legacy tier" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "silver"
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.gold)
      org.mark_as_spammy

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is flagged and unable to make purchases/, pricing_model.error_messages.join
    end

    test "cannot switch from legacy to per seat even if it is a downgrade in price" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "gold"
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business)
      org.mark_as_spammy

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is flagged and unable to make purchases/, pricing_model.error_messages.join
    end

    test "can switch to downgraded plan" do
      org = create :credit_card_org, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.free)
      org.mark_as_spammy

      pricing_model.switch(actor: @actor)

      Timecop.travel(GitHub::Billing.date_in_timezone(org.reload.next_billing_date)) do
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
      end

      assert pricing_model.organization.valid?
      assert org.reload.plan.free?
    end
  end

  context "with a disabled organization" do
    test "cannot switch to upgraded plan when disabled due to payment issue" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "business", seats: 6, disabled: true, billing_attempts: 3
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business_plus)

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Your account is currently locked from purchases/, pricing_model.error_messages.join
    end

    test "can switch to upgraded plan when disabled due to plan limit" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "business", seats: 6, disabled: true
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business_plus)
      Organization.any_instance.stubs(:over_plan_limit?).returns(true)

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert org.reload.plan.business_plus?
    end

    test "can switch to downgraded plan" do
      org = create :credit_card_org, plan: "business", seats: 6, disabled: true
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.free)

      pricing_model.switch(actor: @actor)

      Timecop.travel(GitHub::Billing.date_in_timezone(org.reload.next_billing_date)) do
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
      end

      assert pricing_model.organization.valid?
      assert org.reload.plan.free?
    end
  end

  context "with a trade restricted organization" do
    test "cannot switch to upgraded plan" do
      org = create :credit_card_org, :with_valid_contact_for_billing, :partially_trade_restricted, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.business_plus)

      pricing_model.switch(actor: @actor)

      assert pricing_model.organization.valid?
      assert_match /Due to U.S. trade controls law restrictions, your GitHub account has been restricted/, pricing_model.error_messages.join
    end

    test "can switch to downgraded plan" do
      org = create :credit_card_org, :partially_trade_restricted, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.free)

      pricing_model.switch(actor: @actor)

      Timecop.travel(GitHub::Billing.date_in_timezone(org.reload.next_billing_date)) do
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
      end

      assert pricing_model.organization.valid?
      assert org.reload.plan.free?
    end
  end

  context "switch to per repo" do
    test "only staff can switch from per seat to bronze" do
      org = create :credit_card_org, :with_valid_contact_for_billing, plan: "business", seats: 6
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.bronze)
      refute pricing_model.switch(actor: org.admins.first)
      assert pricing_model.organization.valid?
      assert pricing_model.error_messages.any?
      assert_equal GitHub::Plan.business, org.reload.plan

      staff_actor = create(:staff_admin_user)
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.bronze)
      perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
        assert pricing_model.switch(actor: staff_actor)
      end
      assert pricing_model.organization.valid?
      assert pricing_model.error_messages.none?
      assert_equal GitHub::Plan.bronze, org.reload.plan
    end

    test "can downgrade to free from per seat" do
      org = create :credit_card_org, plan: "business", seats: 6
      assert_nil org.plan_subscription
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: GitHub::Plan.free)

      assert_difference(-> { Billing::BillingTransaction.count }) do
        pricing_model.switch(actor: @actor)
      end

      billing_transaction = org.billing_transactions.last
      refute_nil billing_transaction
      assert_nil billing_transaction.plan_subscription
      assert_predicate billing_transaction, :zero_charge?

      Timecop.travel(GitHub::Billing.date_in_timezone(org.reload.next_billing_date)) do
        perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
      end

      assert pricing_model.organization.valid?
      assert org.reload.plan.free?
    end
  end

  context "switch to business plus plan" do
    test "from free" do
      org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free")
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus

      assert pricing_model.switch(actor: @actor)
      assert_equal GitHub::Plan.business_plus, org.reload.plan
    end
  end

  context "switch to per seat" do
    test "requires that all members have seats" do
      org = create :credit_card_org, :with_valid_contact_for_billing,
        billed_on: GitHub::Billing.today + 10.days
      6.times { org.add_admin(create(:user)) }
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 5)

      refute pricing_model.switch(actor: @actor)
      assert_equal ["Seats must be at least the number of currently filled seats"],
        pricing_model.error_messages
    end

    test "prevents invoiced organizations from switching" do
      pricing_model = build_pricing_model(seats: 10)
      pricing_model.organization.billing_type = "invoice"
      pricing_model.organization.save!
      refute pricing_model.switch(actor: @actor)
      assert_equal ["Your account is being invoiced. Please contact support to make plan changes."], pricing_model.error_messages
    end

    test "requires valid payment information" do
      pricing_model = build_pricing_model(seats: 10)
      pricing_model.organization.payment_method.destroy
      pricing_model.organization.reload
      refute pricing_model.switch(actor: @actor)
      assert_equal ["must have a payment method on file"], pricing_model.error_messages
    end

    test "takes valid payment information" do
      org = create(:organization)
      org.add_admin(user = create(:user))
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 5)


      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        assert pricing_model.switch(actor: user, payment_details: zuora_parsed_payment_details)
      end
      assert org.valid?
      assert org.payment_method
      assert_equal GitHub::Plan.business, org.reload.plan
    end

    test "only synchronizes the account once when a subscription exists and we are updating the payment and TOS" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: GitHub::Plan.free)
      org.add_admin(user = create(:user))
      zuora_successful_customer_account_creation(org)
      org.reload
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 5, new_plan: GitHub::Plan.business)

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
          with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
            assert pricing_model.switch(
              actor: user,
              payment_details: zuora_parsed_payment_details,
              business_owned: true,
              organization_details: { company_name: "GitHub" }
            )
          end
        end
      end
      assert org.valid?
      assert org.payment_method
      assert_equal "GitHub", org.company.name
      assert_equal GitHub::Plan.business, org.reload.plan
    end

    test "allows blank payment information when coupon covers price" do
      ::Billing::PlanSubscription::Transition.expects(:new).never

      org = create(:organization)
      org.add_admin(user = create(:user))
      org.redeem_coupon create(:coupon, discount: 250)
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 5)

      assert pricing_model.switch(actor: user, payment_details: {})
      assert org.valid?
      assert_equal GitHub::Plan.business, org.reload.plan
    end

    test "from a GitHub subscription" do
      FakeZuora.mock
      events = subscribe "account.plan_change"

      actor = create(:user, :with_valid_contact_for_billing)
      pricing_model = build_pricing_model(old_plan: "bronze", seats: 5)
      organization = pricing_model.organization

      # Refund for remaining 9 days of Bronze yearly plan
      percent_service_remaining = percent_service_remaining(pricing_model)
      amount = Billing::Money.new((300_00 * percent_service_remaining).to_i)

      GitHub::Billing.expects(:find_and_refund_transactions_for_amount).
        with(organization, amount.cents)

      assert pricing_model.switch(actor: actor),
        pricing_model.error_messages.join(",")

      organization.reload
      assert_equal GitHub::Plan.business, organization.plan
      assert_equal "year", organization.plan_duration
      assert_equal 5, organization.seats
      assert organization.plan_subscription

      expected_payload = {
        old_plan: "bronze",
        plan: "business",
        old_plan_duration: "year",
        plan_duration: "year",
        old_seats: 5,
        seats: 5,
        old_data_packs: 0,
        asset_packs: 0,
        tos_sha: TosAcceptance.current_sha,
        filled_seats: 2,
        teams_count: 0,
        public_repositories_count: 0,
        private_repositories_count: 0,
        had_active_cloud_trial: false,
        org: organization.login,
        org_id: organization.id,
        actor: actor.login,
        actor_id: actor.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "switch to per seat pricing model *and* change plan duration" do
      FakeZuora.mock
      org = create :credit_card_org,
        :with_valid_contact_for_billing,
        plan: "bronze",
        plan_duration: "month",
        billed_on: GitHub::Billing.today + 10.days
      _plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new \
        org,
        seats: 4,
        plan_duration: "year"
      pricing_model.switch(actor: create(:user))

      assert_equal GitHub::Plan.business, org.plan
      assert_equal "year", org.plan_duration
    end

    test "don't transition if the organization is invalid" do
      Timecop.freeze(Time.zone.local(2015, 5, 22, 8, 0, 0)) do
        org = create :credit_card_org,
          plan: "bronze",
          plan_duration: "year",
          billed_on: GitHub::Billing.today + 10.days

        5.times { org.add_admin(create(:user)) }
        pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 4)

        ::Billing::PlanSubscription::Transition.expects(:new).never

        pricing_model.switch(actor: create(:user))
      end
    end

    test "doesn't transition an organization with a Zuora subscription" do
      org = create(:credit_card_org, :with_valid_contact_for_billing, plan: GitHub::Plan.find!("holmium"))
      _plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
      assert org.zuora_subscription?

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, seats: 5, new_plan: GitHub::Plan.business)

      GitHub::Billing.expects(:find_and_refund_transactions_for_amount).never
      Billing::PlanSubscription::Transition.expects(:new).never

      pricing_model.switch(actor: org.admins.first)

      assert_equal GitHub::Plan.business, org.reload.plan
    end

    test "does not create a zero charge transaction for past due accounts" do
      Timecop.freeze(Time.zone.local(2020, 5, 22, 8, 0, 0)) do
        two_weeks_ago = GitHub::Billing.today - 2.weeks
        org = create :credit_card_org,
          :with_valid_contact_for_billing,
          billed_on: two_weeks_ago,
          plan: "bronze"
        pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org)

        assert_difference "Billing::BillingTransaction.count", 0 do
          pricing_model.switch(actor: org)
        end

        assert_equal GitHub::Plan.business, org.reload.plan
      end
    end
  end

  test "refund for existing service" do
    GitHub.flipper[:remove_org_annual_discount].enable

    # Avoid leap days since we assume 365 days in a year in our assertion for `#final_price`
    travel_to GitHub::Billing.timezone.local(2021, 4, 14, 12, 0, 0) do
      pricing_model = build_pricing_model old_plan: "bronze", seats: 50

      percent_service_remaining = percent_service_remaining(pricing_model)

      # 1 year of 49 seats = $2400
      assert_money 48_00 + 48_00 * 49, pricing_model.renewal_list_price
      # 10 days remaining on bronze yearly plan $300 * 9/365 = $7.40
      assert_money (300_00 * percent_service_remaining).to_i, pricing_model.price_of_remaining_service
      # 1 year of 49 seats = $2400
      assert_money (48_00 + 48_00 * 49).to_i, pricing_model.renewal_price
      assert_money 51_78, pricing_model.final_price
    end
  end

  test "move from legacy to per seat performs immediate upgrade even if it's decrease in price" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: GitHub::Plan.platinum.name)
    new_plan = GitHub::Plan.business
    pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: new_plan, seats: 5)

    assert_no_difference "Billing::PendingPlanChange.count" do
      assert pricing_model.switch(actor: org)
    end

    refute org.pending_cycle_change
    assert_equal new_plan, org.plan
    assert_equal 5, org.seats
  end

  test "move from business plus to business performs a delayed downgrade" do
    organization  = create :credit_card_org, :with_valid_contact_for_billing, seats: 5, plan: "business_plus"
    pricing_model = build_pricing_model organization: organization, new_plan: "business"

    assert pricing_model.switch(actor: organization)
    assert_equal GitHub::Plan.business, organization.pending_cycle_change.plan
  end

  test "updates pending plan change when upgrading" do
    org = create :credit_card_org, :with_valid_contact_for_billing, plan: GitHub::Plan.silver, seats: 20,
      plan_duration: "year", billed_on: GitHub::Billing.today + 1.month

    #downgrade
    pricing_model = build_pricing_model organization: org, old_plan: "silver", new_plan: "bronze"
    pricing_model.switch(actor: org)
    assert_equal GitHub::Plan.bronze, org.pending_cycle_change.plan
    assert_equal GitHub::Plan.silver, org.plan

    #upgrade
    pricing_model = build_pricing_model organization: org, old_plan: "silver", new_plan: "gold", seats: 30
    pricing_model.switch(actor: org)
    assert_equal GitHub::Plan.gold, org.reload.pending_cycle_change.plan
    assert_equal 30, org.pending_cycle_change.seats
    assert_equal GitHub::Plan.gold, org.plan
    assert_equal 30, org.seats
  end

  test "move from monthly to yearly billing performs a delayed change" do
    organization  = create :credit_card_org, :with_valid_contact_for_billing, plan_duration: "month", plan: "bronze"
    pricing_model = build_pricing_model organization: organization,
      old_plan_duration: "month", plan_duration: "year", new_plan: "bronze"

    assert pricing_model.switch(actor: organization)
    assert_equal "year", organization.pending_cycle_change.plan_duration
  end

  test "calculates seat count when checking plan price" do
    org = create :credit_card_org, :with_valid_contact_for_billing, plan: GitHub::Plan.silver, seats: 5,
      plan_duration: "month", billed_on: GitHub::Billing.today + 1.month
    pricing_model = build_pricing_model \
      new_plan: "business",
      old_plan: "silver",
      organization: org,
      seats: 10

    assert_no_difference "Billing::PendingPlanChange.count" do
      pricing_model.switch(actor: org)
    end
    assert_equal GitHub::Plan.business, org.reload.plan
  end

  test "move from free plan with higher number of seats to a paid plan with a lower number of seats is executed immediately" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free", seats: 100)
    new_plan = GitHub::Plan.business
    pricing_model = Billing::PlanChange::PerSeatPricingModel.new(org, new_plan: new_plan)

    assert_no_difference "Billing::PendingPlanChange.count" do
      assert pricing_model.switch(actor: org)
    end

    refute org.pending_cycle_change
    assert_equal new_plan, org.plan
    assert_equal 1, org.seats
  end

  test "records company name and terms-of-service for business-owned organizations" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free")
    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus

    assert pricing_model.switch \
      actor: @actor,
      business_owned: true,
      organization_details: { company_name: "Twitter but for Dogs, Inc." }

    org.reload
    assert_equal 1, org.companies.count
    assert_equal "Twitter but for Dogs, Inc.", org.company.name
    assert_predicate org.terms_of_service, :corporate?
  end

  test "doesn't apply invalid coupon discounts when changing to the business plus plan" do
    org = create(:credit_card_org, plan: "free")
    org.redeem_coupon create(:coupon, discount: 0.25)
    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus,
      seats: 2

    assert_money 42_00, pricing_model.final_price
  end

  test "deactivates trial when upgrading" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free")
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus,
      seats: 5

    pricing_model.switch(actor: org.admins.first)

    org.reload
    refute Billing::EnterpriseCloudTrial.new(org).active?
    assert_equal 5, org.seats
  end

  test "does not cancel the trial if organization saving fails" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free")
    org.add_member(create(:user))
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus,
      seats: 1

    refute pricing_model.switch(actor: org.admins.first)

    assert Billing::EnterpriseCloudTrial.new(org).active?
    assert org.invalid?
  end

  test "doesn't include billing cycle in trial cost" do
    org = create(:credit_card_org, plan: "free")
    org.add_member(create(:user))
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    org.update_attribute :billed_on, GitHub::Billing.today + 5.days

    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus,
      seats: 1

    assert_money 21_00, pricing_model.final_price
  end

  test "resets trial to corporate ToS when upgrading" do
    org = create(:credit_card_org, :with_evaluation_terms, :with_valid_contact_for_billing, plan: "free")
    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus,
      seats: 5

    pricing_model.switch(actor: org.admins.first)

    org.reload

    assert org.reload.terms_of_service.corporate?
  end

  test "runs the upgrade back to enterprise immediately when upgrading at the end of the trial and ensures beta features are enabled" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free", seats: 0, billed_on: 10.days.from_now.to_date)

    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create
    org.pending_plan_changes.incomplete.first.run # simulate trial ending

    org.reload

    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business_plus,
      seats: 5

    pricing_model.switch(actor: org.admins.first)

    org.reload

    assert_empty org.pending_plan_changes.incomplete
    assert org.plan.business_plus?
    assert_equal 5, org.seats
    assert_equal GitHub::Billing.today, org.billed_on
  end

  test "does not update the organization's billing details when there's an error (which also prevents bad data being synced to Zuora)" do
    org = create(:credit_card_org, :with_valid_contact_for_billing, plan: "free", seats: 0, billed_on: 10.days.from_now.to_date)

    trial = Billing::EnterpriseCloudTrial.new(org)
    trial.create

    org.reload

    pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
      new_plan: GitHub::Plan.business,
      seats: 5

    Billing::EnterpriseCloudTrial.any_instance.expects(:deactivate!).raises(RuntimeError)

    assert_raises(RuntimeError) do
      pricing_model.switch(actor: org.admins.first)
    end

    org.reload

    assert org.plan.business_plus?
    assert_equal 50, org.seats
  end

  context "synchronous payment collection" do
    test "does not collect when the feature flag is enabled" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].enable
      org = create(:organization, plan: "free")

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business,
        seats: 5

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        assert_enqueued_jobs(2, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
            assert pricing_model.switch(
              actor: org.admins.first,
              payment_details: zuora_parsed_payment_details,
            )
          end
        end
      end

      org.reload
      assert_equal "business", org.plan.name
      assert_equal 5, org.seats
    end

    test "does not collect when the organization's payment requires a manual transaction (e.g. India RBI)" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:india_based_credit_card_organization, :with_valid_contact_for_billing, plan: "free")
      org.add_admin(user = create(:user))

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business,
        seats: 5

      assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          assert pricing_model.switch(
            actor: user,
          )
        end
      end

      org.reload
      assert_equal "business", org.plan.name
      assert_equal 5, org.seats
    end

    test "only synchronizes once when upgrading from a free to paid plan" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: "free")

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business,
        seats: 5

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
            assert pricing_model.switch(
              actor: org.admins.first,
              payment_details: zuora_parsed_payment_details,
            )
          end
        end
      end

      org.reload
      assert_equal "business", org.plan.name
      assert_equal 5, org.seats
    end

    test "reverts back to free plan when upgrading to paid plan fails" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: "free")

      ::Billing::CollectPaymentForUpgrade.any_instance
        .expects(:synchronize)
        .raises(StandardError.new("error"))

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business,
        seats: 5

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        perform_enqueued_jobs(only: [CollectPaymentForUpgradeJob]) do
          assert pricing_model.switch(
            actor: org.admins.first,
            payment_details: zuora_parsed_payment_details,
          )
        end
      end

      org.reload
      refute Billing::EnterpriseCloudTrial.new(org).active?
      assert_equal "free", org.plan.name
      assert_equal 0, org.seats
    end

    test "only synchronizes once when upgrading from trial" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: "free")
      trial = Billing::EnterpriseCloudTrial.new(org)
      trial.create
      org.reload

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus,
        seats: 5

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          assert_enqueued_jobs(1, only: CollectPaymentForUpgradeJob) do
            assert pricing_model.switch(
              actor: org.admins.first,
              payment_details: zuora_parsed_payment_details,
            )
          end
        end
      end

      org.reload
      refute Billing::EnterpriseCloudTrial.new(org).active?
      assert_equal "business_plus", org.plan.name
      assert_equal 5, org.seats
    end

    test "reverts back to free plan when upgrading from trial fails" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: "free")
      trial = Billing::EnterpriseCloudTrial.new(org)
      trial.create
      org.reload

      ::Billing::CollectPaymentForUpgrade.any_instance
        .expects(:synchronize)
        .raises(StandardError.new("error"))

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus,
        seats: 5

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        perform_enqueued_jobs(only: [CollectPaymentForUpgradeJob]) do
          assert pricing_model.switch(
            actor: org.admins.first,
            payment_details: zuora_parsed_payment_details,
          )
        end
      end

      org.reload
      refute Billing::EnterpriseCloudTrial.new(org).active?
      assert_equal "free", org.plan.name
      assert_equal 0, org.seats
    end

    test "reverts back to team plan when upgrading from trial fails" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: "business", seats: 10)
      trial = Billing::EnterpriseCloudTrial.new(org)
      trial.create
      org.reload

      ::Billing::CollectPaymentForUpgrade.any_instance
        .expects(:synchronize)
        .raises(StandardError.new("error"))

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus,
        seats: 20

      with_live_zuora("zuora_subscription/successful_create_account_with_card") do
        perform_enqueued_jobs(only: [CollectPaymentForUpgradeJob]) do
          assert pricing_model.switch(
            actor: org.admins.first,
            payment_details: zuora_parsed_payment_details,
          )
        end
      end

      org.reload
      refute Billing::EnterpriseCloudTrial.new(org).active?
      assert_equal "business", org.plan.name
      assert_equal 10, org.seats
    end

    test "does not synchronize when the plan is fully covered by a coupon" do
      GitHub.flipper[:skip_immediate_payment_collection_for_plan_or_seat_changes].disable
      org = create(:organization, plan: "free")
      coupon = create(:coupon, discount: "100%")
      org.coupon_redemptions.create(coupon: coupon)

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus,
        seats: 10

      assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
        assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
          assert pricing_model.switch(
            actor: org.admins.first,
          )
        end
      end

      org.reload
      assert_equal "business_plus", org.plan.name
      assert_equal 10, org.seats
    end
  end

  context "plan_and_seat_cost_only" do
    test "passes through plan and seat cost only when true" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        business = create(:business, :with_self_serve_payment, plan_duration: "month", seats: 2)
        business.customer.update(billing_end_date: 1.month.from_now)
        owner = business.owners.first

        create(:billing_product_uuid, :advanced_security)

        result = business.subscribe_to_advanced_security(
          actor: owner,
          seats: 1,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        pricing = Billing::PlanChange::PerSeatPricingModel.new(
          business,
          plan_duration: Business::BillingDependency::MONTHLY_PLAN,
          new_plan: business.plan,
          seats: 3,
          plan_and_seat_cost_only: true,
        )

        assert_money 63_00, pricing.renewal_price
        assert_money 21_00, pricing.price_difference
      end
    end

    test "considers seat price and other subscription items when false" do
      jan_1st = GitHub::Billing.date_in_timezone Date.parse("2023-01-01")
      travel_to jan_1st do
        business = create(:business, :with_self_serve_payment, plan_duration: "month", seats: 2)
        business.customer.update(billing_end_date: 1.month.from_now)
        owner = business.owners.first

        create(:billing_product_uuid, :advanced_security)

        result = business.subscribe_to_advanced_security(
          actor: owner,
          seats: 1,
          billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        assert result.ok?

        pricing = Billing::PlanChange::PerSeatPricingModel.new(
          business,
          plan_duration: Business::BillingDependency::MONTHLY_PLAN,
          new_plan: business.plan,
          seats: 3,
          plan_and_seat_cost_only: false,
        )

        assert_money 112_00, pricing.renewal_price
        assert_money 21_00, pricing.price_difference
      end
    end
  end
end
