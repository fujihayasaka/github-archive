# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SubscriptionTest < GitHub::BillingTestCase
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @pro_user = create(:user, plan: :pro)
  end

  setup do
    synchronize_github_products_to_zuora
  end

  context ".find" do
    test "is nil when a subscription is not found" do
      with_live_zuora("zuora/find_nonexistent_subscription") do
        refute Billing::Zuora::Subscription.find("A-S1234567")
      end
    end

    test "does not make a request to Zuora if the ID is nil" do
      GitHub.zuorest_client.expects(:get_subscription).never

      assert_nil Billing::Zuora::Subscription.find(nil)
    end
  end

  context "#cancel" do
    test "cancels the subscription" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora)
      GitHub.zuorest_client.expects(:get_subscription).with(plan_subscription.zuora_subscription_number).returns({
        "success" => true,
        "contractEffectiveDate" => (GitHub::Billing.today + 1.day).to_s,
        "id" => "subscription-id",
        "subscriptionNumber" => plan_subscription.zuora_subscription_number,
      })
      zuora_subscription = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)

      GitHub.zuorest_client.expects(:cancel_subscription).with(plan_subscription.zuora_subscription_number, {
        cancellationPolicy: "SpecificDate",
        cancellationEffectiveDate: GitHub::Billing.today.to_s,
        runBilling: true,
        collect: false
      }, { "zuora-version" => "211.0" }).returns({})

      zuora_subscription.cancel
    end
  end

  context "#suspend" do
    test "on success, updates the raw subscription's ID" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora)
      GitHub.zuorest_client.expects(:get_subscription).with(plan_subscription.zuora_subscription_number).returns({
        "success" => true,
        "contractEffectiveDate" => (GitHub::Billing.today + 1.day).to_s,
        "id" => "old-subscription-id",
        "subscriptionNumber" => plan_subscription.zuora_subscription_number,
      })
      zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)

      GitHub.zuorest_client.expects(:suspend_subscription).with(plan_subscription.zuora_subscription_number, {
        extendsTerm: false,
        resume: false,
        suspendPolicy: "Today",
      }).returns({ "success" => true, "subscriptionId" => "new-subscription-ID" })

      assert_equal "old-subscription-id", zuora_sub.id

      zuora_sub.suspend

      assert_equal "new-subscription-ID", zuora_sub.id
    end

    test "on failure, does not update the raw subscription's ID" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora)
      GitHub.zuorest_client.expects(:get_subscription).with(plan_subscription.zuora_subscription_number).returns({
        "success" => true,
        "contractEffectiveDate" => (GitHub::Billing.today + 1.day).to_s,
        "id" => "old-subscription-id",
        "subscriptionNumber" => plan_subscription.zuora_subscription_number,
      })
      zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)

      GitHub.zuorest_client.expects(:suspend_subscription).with(plan_subscription.zuora_subscription_number, {
        extendsTerm: false,
        resume: false,
        suspendPolicy: "Today",
      }).returns({ "success" => false, "subscriptionId" => "new-subscription-ID" })

      assert_equal "old-subscription-id", zuora_sub.id

      zuora_sub.suspend

      assert_equal "old-subscription-id", zuora_sub.id
    end
  end

  context "#resume" do
    test "on success, updates the raw subscription's ID" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora)
      GitHub.zuorest_client.expects(:get_subscription).with(plan_subscription.zuora_subscription_number).returns({
        "success" => true,
        "contractEffectiveDate" => (GitHub::Billing.today + 1.day).to_s,
        "id" => "old-subscription-id",
        "subscriptionNumber" => plan_subscription.zuora_subscription_number,
      })
      zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)

      GitHub.zuorest_client.expects(:resume_subscription).with(plan_subscription.zuora_subscription_number, {
        collect: false,
        runBilling: true,
        resumePolicy: "Today",
      }, ::Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER).returns({ "success" => true, "subscriptionId" => "new-subscription-ID" })

      assert_equal "old-subscription-id", zuora_sub.id

      zuora_sub.resume

      assert_equal "new-subscription-ID", zuora_sub.id
    end

    test "on failure, does not update the raw subscription's ID" do
      FakeZuora.mock
      plan_subscription = create(:billing_plan_subscription, :zuora)
      GitHub.zuorest_client.expects(:get_subscription).with(plan_subscription.zuora_subscription_number).returns({
        "success" => true,
        "contractEffectiveDate" => (GitHub::Billing.today + 1.day).to_s,
        "id" => "old-subscription-id",
        "subscriptionNumber" => plan_subscription.zuora_subscription_number,
      })
      zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)

      GitHub.zuorest_client.expects(:resume_subscription).with(plan_subscription.zuora_subscription_number, {
        collect: false,
        runBilling: true,
        resumePolicy: "Today",
      }, ::Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER).returns({ "success" => false, "subscriptionId" => "new-subscription-ID" })

      assert_equal "old-subscription-id", zuora_sub.id

      zuora_sub.resume

      assert_equal "old-subscription-id", zuora_sub.id
    end
  end

  context "#active?" do
    test "returns true when the status is Active" do
      raw_subscription = attributes_for(:zuora_subscription, :active, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert subscription.active?
    end

    test "returns false when the status is not Active" do
      raw_subscription = attributes_for(:zuora_subscription, :cancelled, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      refute subscription.active?
    end
  end

  context "#pending?" do
    test "returns true when the contract effective date is in the future" do
      raw_subscription = attributes_for(:zuora_subscription, :pending, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert subscription.pending?
    end

    test "returns false when the contract effective date is in the past" do
      raw_subscription = attributes_for(:zuora_subscription, :active, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      refute subscription.pending?
    end
  end

  context "#cancelled?" do
    test "returns true when the status is Cancelled" do
      raw_subscription = attributes_for(:zuora_subscription, :cancelled, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert subscription.cancelled?
    end

    test "returns false when the status is not Cancelled" do
      raw_subscription = attributes_for(:zuora_subscription, :active, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      refute subscription.cancelled?
    end
  end

  context "#suspended?" do
    test "returns true when the status is Suspended" do
      raw_subscription = attributes_for(:zuora_subscription, :suspended, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert subscription.suspended?
    end

    test "returns false when the status is not Suspended" do
      raw_subscription = attributes_for(:zuora_subscription, :active, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      refute subscription.suspended?
    end
  end

  context "#past_due?" do
    test "returns true when account has past due invoices" do
      with_live_zuora("zuora/subscriptions/past_due_subscription") do
        org = create(:organization, plan: GitHub::Plan.business)
        zuora_successful_customer_account_creation(org)
        org.reload

        plan_subscription = org.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_subscription = plan_subscription.zuora_subscription

        assert zuora_subscription.past_due?
      end
    end

    test "returns false when no past due invoices are found" do
      raw_subscription = attributes_for(:zuora_subscription, :active, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      Billing::Zuora::Invoice.stubs(:past_due).returns([])

      refute subscription.past_due?
    end
  end

  context "#subscription_items_synchronized?" do
    test "returns true when all subscription items are present in both systems" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)
      subscribable_product = create(:billing_product_uuid, :copilot)
      subscribable_rate_plan = attributes_for(
        :zuora_rate_plan, productRatePlanId: subscribable_product.zuora_product_rate_plan_id
      )
      raw_subscription[:ratePlans] << subscribable_rate_plan

      subscription_item = create(:billing_subscription_item, subscribable: subscribable_product)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert subscription.subscription_items_synchronized?([subscription_item])
    end

    test "returns false when a subscription item is active in GitHub but not Zuora" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)
      subscribable_product = create(:billing_product_uuid, :copilot)
      subscription_item = create(:billing_subscription_item, subscribable: subscribable_product)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      refute subscription.subscription_items_synchronized?([subscription_item])
    end

    test "returns false when a subscription item is active in Zuora but not GitHub" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)
      subscribable_product = create(:billing_product_uuid, :copilot)
      subscribable_rate_plan = attributes_for(
        :zuora_rate_plan, productRatePlanId: subscribable_product.zuora_product_rate_plan_id
      )
      raw_subscription[:ratePlans] << subscribable_rate_plan

      subscription_item = create(:billing_subscription_item)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      refute subscription.subscription_items_synchronized?([subscription_item])
    end
  end

  context "#active_rate_plans" do
    test "returns all active Billing::Zuora::RatePlans objects" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal subscription.active_rate_plans.size, 2
    end

    test "includes rate plans with some inactive rate plan charges" do
      inactive_charge = attributes_for(:zuora_rate_plan_charge, :inactive)
      active_charge = attributes_for(:zuora_rate_plan_charge)

      rate_plan = attributes_for(:zuora_rate_plan, ratePlanCharges: [inactive_charge, active_charge])

      raw_subscription = attributes_for(:zuora_subscription)
      raw_subscription[:ratePlans] = [rate_plan]

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal subscription.active_rate_plans.size, 1
    end

    test "doesn't include rate plans that are scheduled for removal" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)
      raw_subscription[:ratePlans] << attributes_for(:zuora_rate_plan, lastChangeType: "Remove")

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal subscription.active_rate_plans.size, 2
    end
  end

  context "#cancelled_rate_plans" do
    test "returns all inactive Billing::Zuora::RatePlans objects" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)
      raw_subscription[:ratePlans] << attributes_for(:zuora_rate_plan, lastChangeType: "Remove")

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal subscription.cancelled_rate_plans.size, 1
    end
  end

  context "#subscribable_rate_plans" do
    test "return all rate plans for subscribable products" do
      raw_subscription = attributes_for(:zuora_subscription, :with_rate_plans)
      subscribable_product = create(:billing_product_uuid, :copilot)
      subscribable_rate_plan = attributes_for(
        :zuora_rate_plan, productRatePlanId: subscribable_product.zuora_product_rate_plan_id
      )
      raw_subscription[:ratePlans] << subscribable_rate_plan

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal subscription.subscribable_rate_plans.size, 1
      assert_equal(
        T.must(subscription.subscribable_rate_plans.first).product_rate_plan_id,
        subscribable_product.zuora_product_rate_plan_id
      )
    end
  end

  context "#balance" do
    test "returns the balance provided by the Zuora metrics on the account" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_sub = plan_subscription.zuora_subscription

        assert_equal -25063.11, zuora_sub.balance
      end
    end
  end

  context "#seats" do
    test "returns the total number of seats for business plus" do
      with_live_zuora("zuora/subscriptions/organization/business_plus_with_additional_seats") do
        plan = GitHub::Plan.business_plus
        org = create(:organization, plan: plan, seats: 10)
        zuora_successful_customer_account_creation(org)
        org.reload
        plan_subscription = org.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_subscription = plan_subscription.zuora_subscription

        assert_equal 10, zuora_subscription.seats
      end
    end

    test "returns the number of additional seats for a subscription" do
      cassette = "zuora/subscriptions/organization/business_with_additional_seats_munich"

      with_live_zuora(cassette) do
        org = create(:credit_card_organization, plan: GitHub::Plan.business, seats: 15)
        zuora_successful_customer_account_creation(org)
        org.reload
        plan_subscription = org.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_subscription = plan_subscription.zuora_subscription

        assert_equal 14, zuora_subscription.seats
      end
    end

    test "returns 0 for an org with no additional seats past the base unit" do
      with_live_zuora("zuora/subscriptions/organization/business") do
        org = create(:organization, plan: GitHub::Plan.business, seats: 5)
        zuora_successful_customer_account_creation(org)
        org.reload
        plan_subscription = org.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_subscription = plan_subscription.zuora_subscription

        assert_equal 0, zuora_subscription.seats
      end
    end

    test "returns 0 for a per repo plan" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_sub = plan_subscription.zuora_subscription

        assert_equal 0, zuora_sub.seats
      end
    end
  end

  context "#plan" do
    test "returns the first active github plan found" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_sub = plan_subscription.zuora_subscription

        assert_equal GitHub::Plan.pro, zuora_sub.plan
      end
    end

    test "returns only the active GitHub plan" do
      cassette = "zuora/find_subscription_for_org_with_github_upgrades_munich"
      with_live_zuora(cassette) do
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan, :published,
          per_unit: true,
          unit_name: "Seats",
          listing: listing
        listing_plan.sync_to_zuora
        zuora_org = create(:organization, plan: "diamond")

        zuora_successful_customer_account_creation(zuora_org)
        zuora_org.reload
        plan_subscription = zuora_org.plan_subscription
        create :billing_subscription_item,
          subscribable: listing_plan,
          plan_subscription: plan_subscription,
          quantity: 4

        Billing::PlanSubscription::ZuoraSynchronizer.create(plan_subscription.reload)
        zuora_org.update plan: GitHub::Plan.business
        Billing::PlanSubscription::ZuoraSynchronizer.update(plan_subscription.reload)

        zuora_sub = plan_subscription.reload.zuora_subscription
        assert zuora_sub.active_rate_plans.count > 0
        assert_equal GitHub::Plan.business, zuora_sub.plan
      end
    end
  end

  context "#data_packs" do
    test "returns the number of data packs on the subscription" do
      with_live_zuora("zuora/find_subscription_for_user_with_data_packs") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        Asset::Status.create(owner: @pro_user, asset_packs: 10)
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_sub = plan_subscription.zuora_subscription

        refute_nil zuora_sub
        assert_equal 10, zuora_sub.data_packs
      end
    end

    test "returns 0 if there's no active data pack rate plan" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        plan_subscription.reload

        zuora_sub = plan_subscription.zuora_subscription

        assert_equal 0, zuora_sub.data_packs
      end
    end
  end

  context "#payment_amount" do
    test "returns the cost of the subscription for a monthly user" do
      tape = "zuora/find_subscription_for_user_munich"
      with_live_zuora(tape) do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)

        amount = zuora_sub.payment_amount(plan_duration_in_months: @pro_user.plan_duration_in_months)
        assert_equal @pro_user.payment_amount, amount.dollars
      end
    end

    test "returns the correct cost of the subscription for a yearly user" do
      tape = "zuora/find_subscription_for_yearly_user_munich"
      GitHub.zuorest_client.timeout = 30
      with_live_zuora(tape) do
        @pro_user.update(plan_duration: "year")
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)

        amount = zuora_sub.payment_amount(plan_duration_in_months: @pro_user.plan_duration_in_months)
        assert_equal @pro_user.payment_amount, amount.dollars
      end
    end

    test "subtracts discount amount" do
      tape = "zuora/find_subscription_for_coupon_user_munich"
      with_live_zuora(tape) do
        coupon = create(:coupon, discount: 0.5)
        coupon.sync_to_zuora
        @pro_user.redeem_coupon(coupon)
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        @pro_user.update(billed_on: @pro_user.billed_on + 1.month)
        @pro_user.customer.update(bill_cycle_day: @pro_user.billed_on.day)
        plan_subscription = @pro_user.plan_subscription

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
        assert_predicate result, :success?

        @pro_user.reload
        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.plan_subscription.zuora_subscription_number)
        assert_equal 2, zuora_sub.active_rate_plans.count
        discount_in_cents = GitHub::Plan.pro.cost_in_cents * 0.5
        assert_equal Billing::Money.new(discount_in_cents), zuora_sub.discount
        assert_equal @pro_user.payment_amount, zuora_sub.payment_amount(plan_duration_in_months: @pro_user.plan_duration_in_months).dollars
        assert_equal coupon.zuora_id(cycle: @pro_user.plan_duration),
          T.must(zuora_sub.active_rate_plans.last)[:productRatePlanId]
      end
    end
  end

  context "#discount" do
    test "applies the discount to all seats" do
      with_live_zuora("zuora/find_subscription_discount_for_couponed_order") do
        coupon = create(:coupon, discount: 1.0)
        coupon.sync_to_zuora
        organization = create(:organization, plan: "business", seats: 20)
        organization.redeem_coupon(coupon)
        zuora_successful_customer_account_creation(organization)
        organization.reload
        organization.update(billed_on: organization.billed_on + 1.month)
        organization.customer.update(bill_cycle_day: organization.billed_on.day)
        plan_subscription = organization.plan_subscription

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        assert_predicate result, :success?
        assert organization.reload.plan_subscription.zuora_subscription_number
        zuora_sub = plan_subscription.zuora_subscription
        # $25 business plan + 15 additional seats at $9 = $160
        assert_equal Billing::Money.new(160_00), zuora_sub.discount
      end
    end
  end

  context "#charged_through_date_for" do
    test "returns today if there are no charge through dates for a given product rate plan charge id" do
      charge_id = "4242"
      raw_rate_plan = attributes_for(:zuora_rate_plan, ratePlanCharges: [
        attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: charge_id, chargedThroughDate: nil)
      ])
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [raw_rate_plan])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal GitHub::Billing.today, subscription.charged_through_date_for(product_rate_plan_charge_id: charge_id)
    end

    test "returns the charged through date for a given product rate plan charge id" do
      charge_id = "4242"
      charged_through_date = Date.new(2022, 10, 31)
      raw_rate_plan = attributes_for(:zuora_rate_plan, ratePlanCharges: [
        attributes_for(:zuora_rate_plan_charge, productRatePlanChargeId: charge_id, chargedThroughDate: charged_through_date.to_s)
      ])
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [raw_rate_plan])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal charged_through_date, subscription.charged_through_date_for(product_rate_plan_charge_id: charge_id)
    end
  end

  context "#charged_through_date" do
    test "returns today if there are no charge through dates" do
      raw_rate_plan = attributes_for(:zuora_rate_plan, ratePlanCharges: [
        attributes_for(:zuora_rate_plan_charge, chargedThroughDate: nil, billingPeriod: "Month")
      ])
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [raw_rate_plan])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal GitHub::Billing.today, subscription.charged_through_date
    end
  end

  context "#active_charged_through_date" do
    test "returns the charged through date for a given subscription" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription)
        synchronizer.create
        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)
        assert_equal Date.new(2022, 9, 16), zuora_sub.active_charged_through_date
      end
    end

    test "doesn't return the charged through date from an expired charge" do
      raw_rate_plan = attributes_for(:zuora_rate_plan, ratePlanCharges: [
        attributes_for(:zuora_rate_plan_charge, effectiveEndDate: "2018-02-23", chargedThroughDate: "2018-02-23", billingPeriod: "Month"),
        attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, chargedThroughDate: "2018-03-23", billingPeriod: "Month"),
      ])
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [raw_rate_plan])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal Date.parse("2018-03-23"), subscription.active_charged_through_date
    end

    # See https://github.com/github/sponsors/issues/3552
    test "doesn't return the charged through date from a one-time charge" do
      one_time_charge_date = GitHub::Billing.timezone.local(2018, 3, 19)
      one_time_charge_effective_end_date = one_time_charge_date + 1.day
      recurring_charged_through_date = GitHub::Billing.timezone.local(2018, 3, 23)

      travel_to one_time_charge_date do
        product = GitHub::Plan.pro.product_uuid("year")
        raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
          attributes_for(
            :zuora_rate_plan,
            productId: product.zuora_product_id,
            productRatePlanId: product.zuora_product_rate_plan_id,
            productName: "GitHub Developer Plan",
            ratePlanCharges: [
              attributes_for(
                :zuora_rate_plan_charge,
                type: "OneTime",
                effectiveStartDate: one_time_charge_date.to_date.iso8601,
                effectiveEndDate: one_time_charge_effective_end_date.to_date.iso8601,
                chargedThroughDate: one_time_charge_effective_end_date.to_date.iso8601,
                billingPeriod: "Month"
              ),
              attributes_for(
                :zuora_rate_plan_charge,
                effectiveEndDate: nil,
                chargedThroughDate: recurring_charged_through_date.to_date.iso8601,
                billingPeriod: "Month"
              ),
            ]
          )
        ])

        GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
        subscription = Billing::Zuora::Subscription.find!("test")

        assert_equal recurring_charged_through_date.to_date, subscription.active_charged_through_date
      end
    end

    test "returns charged through date from the active GitHub rate plan" do
      product = GitHub::Plan.pro.product_uuid("year")
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(
          :zuora_rate_plan,
          ratePlanCharges: [
            attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, chargedThroughDate: "2018-07-07", billingPeriod: "Month")
          ]
        ),
        attributes_for(
          :zuora_rate_plan,
          productId: product.zuora_product_id,
          productRatePlanId: product.zuora_product_rate_plan_id,
          productName: "GitHub Developer Plan",
          ratePlanCharges: [
            attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, chargedThroughDate: nil),
            attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, chargedThroughDate: "2018-03-23", billingPeriod: "Annual"),
          ]
        )
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal Date.parse("2018-03-23"), subscription.active_charged_through_date
    end

    test "returns sponsors' charged through date even when copilot yearly charge is present" do
      copilot_product = create(:billing_product_uuid, :copilot, billing_cycle: :year)
      sponsors_charged_through_date = "2018-07-07"
      copilot_rate_plan = attributes_for(
        :zuora_rate_plan,
        productId: copilot_product.zuora_product_id,
        productRatePlanId: copilot_product.zuora_product_rate_plan_id,
        productName: "GitHub Copilot",
        ratePlanCharges: [
          attributes_for(
            :zuora_rate_plan_charge,
            productRatePlanChargeId:  copilot_product.zuora_product_rate_plan_charge_ids[:flat],
            chargedThroughDate: "2018-03-23",
            billingPeriod: "Annual"
          )
        ]
      )
      sponsor_rate_plan = attributes_for(:zuora_rate_plan, ratePlanCharges: [
        attributes_for(
          :zuora_rate_plan_charge,
          chargedThroughDate: sponsors_charged_through_date,
          billingPeriod: "Month"
        )
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test1").returns({ success: true, ratePlans: [sponsor_rate_plan, copilot_rate_plan] })
      subscription = Billing::Zuora::Subscription.find!("test1")
      assert_equal Date.parse(sponsors_charged_through_date), subscription.active_charged_through_date

      # Just to ensure that order doesn't matter
      GitHub.zuorest_client.expects(:get_subscription).with("test2").returns({ success: true, ratePlans: [copilot_rate_plan, sponsor_rate_plan] })
      subscription = Billing::Zuora::Subscription.find!("test2")
      assert_equal Date.parse(sponsors_charged_through_date), subscription.active_charged_through_date
    end

    test "returns copilot charged through date when it's the only charge present" do
      copilot_product = create(:billing_product_uuid, :copilot, billing_cycle: :year)
      copilot_charged_through_date = "2018-03-23"

      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [{
        productId: copilot_product.zuora_product_id,
        productRatePlanId: copilot_product.zuora_product_rate_plan_id,
        productName: "GitHub Copilot",
        ratePlanCharges: [{
          productRatePlanChargeId:  copilot_product.zuora_product_rate_plan_charge_ids[:flat],
          chargedThroughDate: "2018-03-23",
          billingPeriod: "Annual"
        }]
      }])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal Date.parse(copilot_charged_through_date), subscription.active_charged_through_date
    end

    test "returns charge through date of first active rate plan if there is no 'GitHub Plan' Rate Plan" do
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(:zuora_rate_plan, ratePlanCharges: [
          attributes_for(
            :zuora_rate_plan_charge,
            effectiveEndDate: nil,
            chargedThroughDate: "2018-07-07",
            billingPeriod: "Month"
          )
        ]),
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal Date.parse("2018-07-07"), subscription.active_charged_through_date
    end

    test "returns a charged through date a month ahead if the first charge is Usage based" do
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(:zuora_rate_plan, ratePlanCharges: [
          attributes_for(:zuora_rate_plan_charge, type: "Usage", effectiveEndDate: nil, chargedThroughDate: "2018-07-07", billingPeriod: "Month"),
        ]),
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal Date.parse("2018-08-07"), subscription.active_charged_through_date
    end

    test "returns nil if there are no charged_through_dates" do
      product = GitHub::Plan.pro.product_uuid("year")
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(
          :zuora_rate_plan,
          productId: product.zuora_product_id,
          productRatePlanId: product.zuora_product_rate_plan_id,
          productName: "GitHub Developer Plan",
          ratePlanCharges: [
            attributes_for(
              :zuora_rate_plan_charge,
              effectiveEndDate: "2018-02-23", chargedThroughDate: nil, billingPeriod: "Month"
            )
          ]
        ),
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_nil subscription.active_charged_through_date
    end
  end

  context "#id" do
    test "returns the versioned subscription id" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)

        assert_equal 32, zuora_sub.id.length
      end
    end
  end

  context "#number" do
    test "returns the short subscription id" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)

        assert zuora_sub.number
      end
    end
  end

  context "#plan_duration" do
    test "returns year for a yearly subscription" do
      with_live_zuora("zuora/find_subscription_for_yearly_user") do
        @pro_user.update(plan_duration: User::BillingDependency::YEARLY_PLAN)
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)

        assert_equal "year", zuora_sub.plan_duration
      end
    end

    test "returns month for a monthly subscription" do
      with_live_zuora("zuora/find_subscription_for_user") do
        zuora_successful_customer_account_creation(@pro_user)
        @pro_user.reload
        plan_subscription = @pro_user.plan_subscription
        Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        zuora_sub = Billing::Zuora::Subscription.find!(@pro_user.reload.plan_subscription.zuora_subscription_number)

        assert_equal "month", zuora_sub.plan_duration
      end
    end

    test "returns year when plan is legacy zuora product name" do
      product = GitHub::Plan.find("californium").product_uuid("year")
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(
          :zuora_rate_plan,
          productId: product.zuora_product_id,
          productRatePlanId: product.zuora_product_rate_plan_id,
          productName: "GitHub's Team plan (Annual Californium)",
          ratePlanCharges: [
            attributes_for(:zuora_rate_plan_charge, billingPeriod: "Annual", effectiveEndDate: nil)
          ]
        )
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal "year", subscription.plan_duration
    end

    test "returns year for varied billing period charges but has a annual charge" do
      product = GitHub::Plan.pro.product_uuid("year")
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(:zuora_rate_plan, ratePlanCharges: [
          attributes_for(:zuora_rate_plan_charge, billingPeriod: "Month", effectiveEndDate: nil),
        ]),
        attributes_for(:zuora_rate_plan, ratePlanCharges: [
          attributes_for(:zuora_rate_plan_charge, billingPeriod: "Month", effectiveEndDate: nil),
        ]),
        attributes_for(
          :zuora_rate_plan,
          productId: product.zuora_product_id,
          productRatePlanId: product.zuora_product_rate_plan_id,
          productName: "GitHub Developer Plan",
          ratePlanCharges: [attributes_for(:zuora_rate_plan_charge, billingPeriod: "Annual", effectiveEndDate: nil)]
        )
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal "year", subscription.plan_duration
    end

    test "returns year for varied billing period charges if there is no Active 'GitHub Plan' rate plan" do
      raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [
        attributes_for(:zuora_rate_plan, ratePlanCharges: [
          attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, billingPeriod: "Annual")
        ]),
        attributes_for(:zuora_rate_plan, ratePlanCharges: [
          attributes_for(:zuora_rate_plan_charge, effectiveEndDate: nil, billingPeriod: "Month")
        ]),
      ])

      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = Billing::Zuora::Subscription.find!("test")

      assert_equal "year", subscription.plan_duration
    end
  end

  context "#purpose" do
    test "returns :general if gateway field is nil" do
      raw_subscription = attributes_for(:zuora_subscription, :active,
        Billing::PlanSubscription::PAYMENT_GATEWAY_FIELD => nil,
      )
      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = T.must(Billing::Zuora::Subscription.find("test"))
      assert_equal :general, subscription.purpose
    end

    test "returns :general if gateway field not the sponsors gateway name" do
      raw_subscription = attributes_for(:zuora_subscription, :active,
        Billing::PlanSubscription::PAYMENT_GATEWAY_FIELD => Billing::Zuora::PaymentGateway::STRIPE_V2,
      )
      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = T.must(Billing::Zuora::Subscription.find("test"))
      assert_equal :general, subscription.purpose
    end

    test "returns :sponsors if gateway field is sponsors gateway name" do
      raw_subscription = attributes_for(:zuora_subscription, :active,
        Billing::PlanSubscription::PAYMENT_GATEWAY_FIELD => Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2,
      )
      GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)
      subscription = T.must(Billing::Zuora::Subscription.find("test"))
      assert_equal :sponsors, subscription.purpose
    end
  end
end
