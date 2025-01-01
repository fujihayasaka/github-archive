# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PricingTest < GitHub::BillingTestCase
  include ::Billing::ApiTestHelpers
  include ::Billing::ActionsTestHelpers

  fixtures do
    business_plan_subscription = create(:billing_plan_subscription, :business_owned)
    @business = business_plan_subscription.business
  end

  setup do
    create(:billing_product_uuid, :advanced_security)
    create(:billing_product_uuid, :advanced_security, :yearly)
    create(:billing_product_uuid, :copilot)
    create(:billing_product_uuid, :copilot, :yearly)
  end

  test "raises if user, plan_subscription, plan, and plan_duration arguments are all nil" do
    assert_raises ArgumentError do
      Billing::Pricing.new
    end
  end

  test "raises if both coupon and discount are provided" do
    assert_raises ArgumentError do
      Billing::Pricing.new(plan_duration: "month", coupon: Coupon.new, discount: 5)
    end
  end

  test "calculates pricing for user monthly plan" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents, pricing.discounted
    assert_money plan.yearly_cost_in_cents, pricing.annual_recurring_revenue
  end

  test "calculates pricing for org yearly plan" do
    org = create :organization, \
      plan: GitHub::Plan.business_plus,
      seats: 2,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: org.reload)

    # 2 seats at $252 a year = $504
    assert_money 252_00, pricing.plan_cost
    assert_money 504_00, pricing.plan_and_seat_cost
    assert_money 252_00, pricing.discounted_plan_cost
    assert_money 504_00, pricing.discounted
    assert_money 504_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for business monthly plan" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    pricing = Billing::Pricing.new(account: @business)

    # $21 a month
    assert_money 21_00, pricing.plan_cost
    assert_money 21_00, pricing.discounted_plan_cost

    # 100 seats at $21 a month
    assert_money 2100_00, pricing.plan_and_seat_cost
    assert_money 2100_00, pricing.discounted

    # 100 seats at $21 a month for 12 months
    assert_money 25200_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for business monthly plan with a coupon" do
    coupon = create :coupon, discount: 1000
    @business.reload.update_attribute(:plan_duration, "month")
    owner = @business.owners.first
    @business.redeem_coupon coupon, actor: owner
    pricing = Billing::Pricing.new(account: @business.reload)

    # $21 a month
    assert_money 21_00, pricing.plan_cost
    assert_money 10_00, pricing.plan_discount
    assert_money 11_00, pricing.discounted_plan_cost

    # 100 seats at $21 a month
    assert_money 2100_00, pricing.plan_and_seat_cost
    assert_money 1100_00, pricing.discounted

    # 100 seats at $21 a month for 12 months at a $10 discount per seat per month
    assert_money 13200_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for business yearly plan" do
    plan = @business.plan
    pricing = Billing::Pricing.new(account: @business)

    # 100 seats at $252 a year
    assert_money 252_00, pricing.plan_cost
    assert_money 252_00, pricing.discounted_plan_cost
    assert_money 25200_00, pricing.plan_and_seat_cost
    assert_money 25200_00, pricing.discounted
    assert_money 25200_00, pricing.annual_recurring_revenue
  end

  test "prorates the discounted price for a user plan" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user, service_remaining: 0.25)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents * 0.25, pricing.prorated_plan_cost
    assert_money plan.cost_in_cents * 0.25, pricing.discounted
  end

  test "prorates the discounted price for a business plan" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    plan = @business.plan
    pricing = Billing::Pricing.new(account: @business, service_remaining: 0.25)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents * 0.25, pricing.prorated_plan_cost
    assert_money plan.cost_in_cents * 0.25 * 100, pricing.discounted
  end

  test "prorates the discounted price for additional seats for an org" do
    org = create :organization, \
      plan: GitHub::Plan.business,
      seats: 6,
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: org, service_remaining: 0.25)

    # $25 plan + 5 additional seats at $9 = $34 * 0.25 = $8.50
    assert_money 1_00, pricing.prorated_plan_cost
    assert_money 5_00, pricing.prorated_seat_cost
    assert_money 6_00, pricing.discounted
  end

  test "prorates the discounted price for additional seats for a business" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    pricing = Billing::Pricing.new(account: @business, service_remaining: 0.25)

    assert_money 5_25, pricing.prorated_plan_cost
    assert_money 519_75, pricing.prorated_seat_cost
    assert_money 525_00, pricing.discounted
  end

  test "calculates pricing for a per seat plan with base units and additional seats for an org" do
    org = create :organization, \
      plan: GitHub::Plan.business,
      seats: 6,
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: org)

    # $25 plan + 1 additional seat at $9 = $34
    assert_money 4_00, pricing.plan_cost
    assert_money 4_00, pricing.discounted_plan_cost
    assert_money 20_00, pricing.seat_cost
    assert_money 20_00, pricing.discounted_seat_cost
    assert_money 24_00, pricing.discounted
    assert_money 288_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a per seat plan with base units and additional seats for a business" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    pricing = Billing::Pricing.new(account: @business)

    assert_money 21_00, pricing.plan_cost
    assert_money 21_00, pricing.discounted_plan_cost
    assert_money 2079_00, pricing.seat_cost
    assert_money 2079_00, pricing.discounted_seat_cost
    assert_money 2100_00, pricing.discounted
    assert_money 25200_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a per seat plan with base units and unused seats for an org" do
    org = create :organization, \
      plan: GitHub::Plan.business,
      seats: 5,
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: org, seats: 1)

    assert_money 4_00, pricing.plan_cost
    assert_money 4_00, pricing.discounted_plan_cost
    assert_money 0_00, pricing.seat_cost
    assert_money 0_00, pricing.discounted_seat_cost
    assert_money 4_00, pricing.discounted
    assert_money 48_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a monthly plan with a redeemed dollar-off coupon" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: plan.cost - 2)
    user.redeem_coupon(coupon)
    discount_in_cents = coupon.discount * 100

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a yearly plan with a redeemed dollar-off coupon" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)
    discount = plan.cost - 1
    discount_in_cents = discount * 100
    coupon = create(:coupon, discount: discount)
    user.redeem_coupon(coupon)

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.yearly_cost_in_cents, pricing.plan_cost
    assert_money plan.yearly_cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents * 12, pricing.plan_discount
    assert_money discount_in_cents * 12, pricing.discount
    assert_money plan.yearly_cost_in_cents, pricing.plan_and_seat_cost
    assert_money plan.yearly_cost_in_cents - (discount_in_cents * 12), pricing.discounted_plan_cost
    assert_money plan.yearly_cost_in_cents - (discount_in_cents * 12), pricing.discounted
    assert_money plan.yearly_cost_in_cents - (discount_in_cents * 12), pricing.annual_recurring_revenue
  end

  test "calculates pricing for a monthly plan with a redeemed percentage-off coupon" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 0.2)
    user.redeem_coupon(coupon)
    discount_in_cents = plan.cost_in_cents * coupon.discount

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a yearly plan with a redeemed percentage-off coupon" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 0.2)
    discount_in_cents = plan.yearly_cost_in_cents * coupon.discount
    user.redeem_coupon(coupon)

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.yearly_cost_in_cents, pricing.plan_cost
    assert_money plan.yearly_cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.yearly_cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.yearly_cost_in_cents - discount_in_cents, pricing.discounted
    assert_money plan.yearly_cost_in_cents - discount_in_cents, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a plan with a hypothetical dollar-off coupon" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: plan.cost - 2)
    discount_in_cents = coupon.discount * 100

    pricing = Billing::Pricing.new(account: user, coupon: coupon)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a plan with a hypothetical percentage-off coupon" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 0.2)
    discount_in_cents = plan.cost_in_cents * 0.2

    pricing = Billing::Pricing.new(account: user, coupon: coupon)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a plan with a hypothetical dollar-off discount for a user" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)

    discount = plan.cost - 1
    pricing = Billing::Pricing.new(account: user, discount: discount)
    discount_in_cents = discount * 100

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a plan with a hypothetical dollar-off discount for a business" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    plan = @business.plan
    discount = plan.cost - 1
    pricing = Billing::Pricing.new(account: @business, seats: 1, discount: discount)
    discount_in_cents = discount * 100

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a plan with a hypothetical percentage-off discount for a user" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)

    discount = 0.2
    discount_in_cents = plan.cost_in_cents * discount
    pricing = Billing::Pricing.new(account: user, discount: discount)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a plan with a hypothetical percentage-off discount for a business" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    plan = @business.plan
    discount = 0.2
    discount_in_cents = plan.cost_in_cents * discount
    pricing = Billing::Pricing.new(account: @business, seats: 1, discount: discount)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money discount_in_cents, pricing.plan_discount
    assert_money discount_in_cents, pricing.discount
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents - discount_in_cents, pricing.discounted
    assert_money (plan.cost_in_cents - discount_in_cents) * 12, pricing.annual_recurring_revenue
  end

  test "calculates pricing when the coupon is greater than the plan price" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 10)
    user.redeem_coupon(coupon)

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money plan.cost_in_cents, pricing.plan_discount
    assert_money plan.cost_in_cents, pricing.discount
    assert_money 0_00, pricing.discounted_plan_cost
    assert_money 0_00, pricing.discounted
    assert_money 0_00, pricing.annual_recurring_revenue
  end

  test "does not include coupons which will expire prior to the next billing date" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 5, duration: 1)

    Timecop.freeze(1.month.ago) { user.redeem_coupon(coupon) }

    pricing = Billing::Pricing.new(account: user)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money 0_00, pricing.plan_discount
    assert_money 0_00, pricing.discount
    assert_money plan.cost_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents, pricing.discounted
    assert_money plan.yearly_cost_in_cents, pricing.annual_recurring_revenue
  end

  test "does not apply a plan-specific coupon to the wrong plan" do
    plan = GitHub::Plan.pro
    user = create(:user, plan: plan, plan_duration: "month")
    coupon = create(:coupon, discount: plan.cost - 1, plan: GitHub::Plan.gold)
    plan_subscription = create(:billing_plan_subscription, user: user)

    pricing = Billing::Pricing.new(plan_subscription: plan_subscription, coupon: coupon)

    assert_money plan.cost_in_cents, pricing.plan_cost
    assert_money plan.cost_in_cents, pricing.undiscounted
    assert_money 0_00, pricing.plan_discount
    assert_money 0_00, pricing.discount
    assert_money plan.cost_in_cents, pricing.discounted_plan_cost
    assert_money plan.cost_in_cents, pricing.discounted
    assert_money plan.yearly_cost_in_cents, pricing.annual_recurring_revenue
  end

  test "apportions a percentage-off discount across all discountable items" do
    org = create :organization, \
      plan: GitHub::Plan.business,
      seats: 10,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    Asset::Status.create! owner: org, asset_packs: 3

    coupon = create(:coupon, discount: 0.2)
    org.redeem_coupon(coupon)

    pricing = Billing::Pricing.new(account: org)



    assert_money 4_00, pricing.plan_cost
    assert_money 80, pricing.plan_discount
    assert_money 3_20, pricing.discounted_plan_cost

    assert_money 36_00, pricing.seat_cost
    assert_money 7_20, pricing.seat_discount
    assert_money 28_80, pricing.discounted_seat_cost

    assert_money 15_00, pricing.data_pack_cost
    assert_money 3_00, pricing.data_pack_discount
    assert_money 12_00, pricing.discounted_data_pack_cost
  end

  test "calculates pricing for a plan with a free trial" do
    organization = create(:organization, plan: GitHub::Plan::BUSINESS, seats: 50)
    create(:billing_plan_trial, :active, user: organization, plan: GitHub::Plan::BUSINESS)

    pricing = Billing::Pricing.new(account: organization)

    assert_money 0, pricing.plan_cost
    assert_money 0, pricing.seat_cost
  end

  test "calculates pricing for data packs when on the free plan" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription)
    Asset::Status.create! owner: user, asset_packs: 3

    pricing = Billing::Pricing.new(account: user)

    # 3 data packs at $5 = $15
    assert_money 0_00, pricing.plan_and_seat_cost
    assert_money 15_00, pricing.data_pack_cost
    assert_money 15_00, pricing.discounted_data_pack_cost
    assert_money 15_00, pricing.discounted
    assert_money 180_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for data packs when on a yearly plan" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: GitHub::Plan.pro,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)
    Asset::Status.create! owner: user, asset_packs: 2

    pricing = Billing::Pricing.new(account: user)

    # 2 data packs at $5 + $7 pro plan = $17 per month
    # $17 * 12 months = $204 per year
    assert_money plan.yearly_cost_in_cents, pricing.plan_cost
    assert_money plan.yearly_cost_in_cents, pricing.plan_and_seat_cost
    assert_money 120_00, pricing.data_pack_cost
    assert_money 120_00, pricing.discounted_data_pack_cost
    assert_money plan.yearly_cost_in_cents + 120_00, pricing.discounted
    assert_money plan.yearly_cost_in_cents + 120_00, pricing.annual_recurring_revenue
  end

  test "prorates the discounted price for data packs" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription)
    Asset::Status.create! owner: user, asset_packs: 3

    pricing = Billing::Pricing.new(account: user, service_remaining: 0.25)

    # 3 data packs at $5 = $15 * 0.25 = $3.75
    assert_money 15_00, pricing.data_pack_cost
    assert_money 15_00, pricing.discounted_data_pack_cost
    assert_money 3_75, pricing.prorated_data_pack_cost
    assert_money 3_75, pricing.discounted
  end

  test "calculates pricing for shared storage" do
    user = create :credit_card_user
    user.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)
    GitHub::Billing.stubs(:now).returns((GitHub::Billing.timezone.now).beginning_of_day + 1.hour)

    # One hour of storage usage of 60 GB
    mock_calculate_usage_quotes_response(
      product_name: "shared_storage",
      product_sku_name: "default",
      total_proposed_usage_effective_quantity: 60.gigabytes
    )
    # Used as the dotcom's knowledge of the current storage amount
    # on disk for estimating usage from now to the end of the month
    create(
      :shared_storage_current_usage, :private_visibility,
      owner: user, billable_owner: user.billable_owner,
      aggregate_size_in_bytes: 60.gigabytes,
      effective_at: GitHub::Billing.now
    )

    pricing = Billing::Pricing.new(account: user)

    # No overages allowed
    assert_money 0, pricing.estimated_shared_storage_cost

    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    # ((0.25 * 100) / 1024) * ((60 * 1024) - 512) = 14.875
    assert_money 14_88, pricing.estimated_shared_storage_cost
  end

  test "calculates pricing for actions when on the free plan" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    assert_money 0, pricing.actions_cost
  end

  test "calculates pricing for actions when on a paid plan for a user" do
    user = create :credit_card_user,
      plan: GitHub::Plan.pro,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    mock_get_usage_breakdown(
      products: create_product_breakdown_array(
        name: "actions",
        skus: [create_skus_breakdown_hash(sku: "linux", estimated_overage_charge: 2400)],
      ),
    )

    pricing = Billing::Pricing.new(account: user)

    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    # (6000 minutes used - 3000 included minutes) * $0.008 / minute
    assert_money 24_00, pricing.actions_cost
  end

  test "only calculates pricing for overage minutes for a user" do
    user = create :credit_card_user,
      plan: GitHub::Plan.pro,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    mock_get_usage_breakdown(
      products: create_product_breakdown_array(
        name: "actions",
        skus: [create_skus_breakdown_hash(sku: "linux", estimated_overage_charge: 2400)],
      )
    )

    pricing = Billing::Pricing.new(account: user)
    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    assert_money 24_00, pricing.actions_cost
  end

  test "only calculates pricing for overage minutes for a business" do
    mock_get_usage_breakdown(
      products: create_product_breakdown_array(
        name: "actions",
        skus: [create_skus_breakdown_hash(sku: "linux", estimated_overage_charge: 2400)],
      )
    )

    pricing = Billing::Pricing.new(account: @business)
    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    # (53000 minutes used - 50000 included minutes) * $0.008 / minute
    assert_money 24_00, pricing.actions_cost
  end

  test "#actions_cost returns zero for user when not opted in to overages" do
    user = create :user,
      plan: GitHub::Plan.pro,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    assert_money 0, pricing.actions_cost
  end

  test "#actions_cost returns zero for business when not opted in to overages" do
    pricing = Billing::Pricing.new(account: @business)

    assert_money 0, pricing.actions_cost
  end

  test "#package_downloads_cost returns zero for user when not opted in to overages" do
    user = create :user,
      plan: GitHub::Plan.pro,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    assert_money 0, pricing.package_downloads_cost
  end

  test "#package_downloads_cost returns zero for business when not opted in to overages" do
    pricing = Billing::Pricing.new(account: @business)

    assert_money 0, pricing.package_downloads_cost
  end

  test "#package_downloads_cost returns the cost of billable gigabytes for a user" do
    user = create :credit_card_user,
      plan: GitHub::Plan.pro,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    stub_shared_products_usage_response(proposed_gigabytes: (user.plan.package_registry_included_bandwidth + 1).gigabytes)

    # (6GB  used - 5GB included ) * $0.5 / GB
    pricing = Billing::Pricing.new(account: user)
    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    assert_money 50, pricing.package_downloads_cost
  end

  test "#package_downloads_cost returns the cost of billable gigabytes for a business" do
    stub_shared_products_usage_response(
      proposed_gigabytes: (@business.plan.package_registry_included_bandwidth + 1).gigabytes
    )

    # (101GB  used - 100GB included ) * $0.5 / GB
    pricing = Billing::Pricing.new(account: @business)
    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    assert_money 50, pricing.package_downloads_cost
  end

  test "calculates pricing with a monthly marketplace subscription" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    sub_item = create :billing_subscription_item,
      plan_subscription: user.plan_subscription,
      subscribable: listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(account: user)

    assert_money 10_00, pricing.marketplace_item_cost
    assert_money 10_00, pricing.discounted
    assert_equal [sub_item], pricing.marketplace_items

    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue
  end

  test "does not add in the cost of sponsorable listings to ARR calculations" do
    user = create :credit_card_user

    create(:billing_plan_subscription, user: user, customer: user.customer)

    sponsors_tier = create(:sponsors_tier, state: :published)
    sponsors_sub_item = create :sponsors_subscription_item,
      account: user,
      subscribable: sponsors_tier,
      quantity: 10

    mp_listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    mp_sub_item = create :billing_subscription_item,
      account: user,
      subscribable: mp_listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(account: user)

    assert_equal [sponsors_sub_item], pricing.recurring_sponsorable_items
    assert_equal [mp_sub_item], pricing.marketplace_items

    # NOTE: same assertion as a previous test, but added a sponsorable listing
    # If it was adding sponsorships, we'd expect $150_00 of arr as
    # (10 quantity * $1) / month * 12 months = $120_00
    # but instead the calculation is as follows:
    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing with a yearly marketplace subscription" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)
    listing_plan = create :marketplace_listing_plan,
      :verified_listing,
      monthly_price_in_cents: 10_00,
      yearly_price_in_cents: 100_00
    create :billing_subscription_item,
      plan_subscription: user.plan_subscription,
      subscribable: listing_plan,
      quantity: 2

    pricing = Billing::Pricing.new(account: user)

    # 2 subscription items at $100 a year = $200
    assert_money 200_00, pricing.marketplace_item_cost
    assert_money 200_00, pricing.discounted
    # $200/year * 5% marketplace cut = $10
    assert_money 10_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing with a marketplace subscription with a free trial" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    listing_plan = create(:marketplace_listing_plan, :free_trial, monthly_price_in_cents: 10_00)
    create :billing_subscription_item,
      :free_trial,
      plan_subscription: user.plan_subscription,
      subscribable: listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(account: user)

    assert_money 0_00, pricing.marketplace_item_cost
    assert_money 0_00, pricing.discounted
    assert_money 0_00, pricing.annual_recurring_revenue
  end

  test "calculates post-trial pricing with a marketplace subscription on free trial" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    listing_plan = create(:marketplace_listing_plan, :free_trial, monthly_price_in_cents: 10_00)
    create :billing_subscription_item,
      plan_subscription: user.plan_subscription,
      subscribable: listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(account: user, use_trial_prices: false)

    assert_money 10_00, pricing.marketplace_item_cost
    assert_money 10_00, pricing.discounted

    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing with a marketplace subscription after free trial" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    listing_plan = create(:marketplace_listing_plan, :free_trial, monthly_price_in_cents: 10_00)
    subscription_item = create :billing_subscription_item,
      plan_subscription: user.plan_subscription,
      subscribable: listing_plan,
      quantity: 1
    subscription_item.update!(free_trial_ends_on: 1.month.ago)

    pricing = Billing::Pricing.new(account: user.reload)

    assert_money 10_00, pricing.marketplace_item_cost
    assert_money 10_00, pricing.discounted

    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for a marketplace subscription alone" do
    listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    subscription_item = Billing::SubscriptionItem.new \
      subscribable: listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(plan_duration: "month", subscription_item: subscription_item)

    assert_money 10_00, pricing.discounted
  end

  test "calculates pricing for multiple marketplace subscriptions" do
    subscription_items = 3.times.map do |i|
      listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: i.succ * 1000)
      Billing::SubscriptionItem.new \
        subscribable: listing_plan,
        quantity: 1
    end

    pricing = Billing::Pricing.new(plan_duration: "month", subscription_items: subscription_items)

    # $10 subscription + $20 subscription + $30 subscription = $60
    assert_money 60_00, pricing.discounted
  end

  test "calculates pricing for pending marketplace subscription changes" do
    Timecop.freeze("2018-02-01") do
      user = create(:user, plan_duration: "month", billed_on: Date.new(2018, 3, 1))
      listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
      pending_change = create(:billing_pending_plan_change, user: user, active_on: Date.new(2018, 2, 15))
      pending_subscription_item_change = Billing::PendingSubscriptionItemChange.new \
        pending_plan_change: pending_change,
        subscribable: listing_plan,
        quantity: 1

      pricing = Billing::Pricing.new(plan_duration: "month", subscription_item: pending_subscription_item_change)

      assert_money 5_00, pricing.discounted
    end
  end

  test "accepts both subscription_item and subscription_items arguments" do
    subscription_items = 3.times.map do |i|
      listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: i.succ * 1000)
      Billing::SubscriptionItem.new \
        subscribable: listing_plan,
        quantity: 1
    end

    pricing = Billing::Pricing.new(
      plan_duration: "month",
      subscription_item: subscription_items.shift,
      subscription_items: subscription_items,
    )

    # $10 subscription + $20 subscription + $30 subscription = $60
    assert_money 60_00, pricing.discounted
  end

  test "prorates the discounted price for copilot, marketplace, and sponsorship subscriptions" do
    user_with_sponsorship = create :credit_card_user,
      plan: GitHub::Plan.free,
      plan_duration: "month"
    listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    create :billing_subscription_item,
      account: user_with_sponsorship,
      subscribable: listing_plan,
      quantity: 1

    tier = create(:sponsors_tier, :published, monthly_price_in_cents: 10_00)
    create :sponsors_subscription_item,
      account: user_with_sponsorship,
      subscribable: tier,
      quantity: 1

    create :billing_subscription_item, :paid,
      account: user_with_sponsorship,
      subscribable: create(:billing_product_uuid, :copilot)

    pricing = Billing::Pricing.new(account: user_with_sponsorship, service_remaining: 0.25)

    assert_money 10_00, pricing.marketplace_item_cost
    assert_money 2_50, pricing.prorated_marketplace_item_cost

    assert_money 10_00, pricing.recurring_sponsorable_item_cost
    assert_money 2_50, pricing.prorated_recurring_sponsorable_item_cost

    assert_money 10_00, pricing.addons_cost
    assert_money 2_50, pricing.prorated_addon_items_cost

    assert_money 7_50, pricing.discounted
  end

  test "does not apply coupons to addon items, marketplace items, or sponsorship items" do
    plan = GitHub::Plan.pro
    user_with_sponsorship = create :user,
      plan: plan,
      plan_duration: "month"
    coupon = create(:coupon, discount: 10)
    user_with_sponsorship.redeem_coupon(coupon)

    listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    create :billing_subscription_item,
      account: user_with_sponsorship,
      subscribable: listing_plan,
      quantity: 1
    tier = create(:sponsors_tier, :published, monthly_price_in_cents: 1_00)
    create :sponsors_subscription_item,
      account: user_with_sponsorship,
      subscribable: tier,
      quantity: 1
    create :billing_subscription_item, :paid,
      account: user_with_sponsorship,
      subscribable: create(:billing_product_uuid, :copilot)
    create :billing_subscription_item, :paid,
      account: user_with_sponsorship,
      subscribable: create(:billing_product_uuid, :advanced_security)

    pricing = Billing::Pricing.new(account: user_with_sponsorship)

    # $7 plan + $10 marketplace item + $1 sponsorship item + $10 copilot item + $49 advanced security item
    assert_money plan.cost_in_cents + 10_00 + 1_00 + 10_00 + 49_00, pricing.undiscounted
    # $10 coupon applied to $7 plan
    assert_money plan.cost_in_cents, pricing.discount
    # Just the $10 copilot, $10 marketplace item and $1 sponsorship item, since the plan was covered by the coupon
    assert_money 10_00 + 1_00 + 10_00 + 49_00, pricing.discounted

    # NOTE: doesn't include sponsorship item because its not revenue
    # $588 GHAS ARR, $120 Monthly Copilot ARR, $10/month marketplace item * 12 months * 5% marketplace cut = $6
    assert_money 588_00 + 120_00 + 6_00, pricing.annual_recurring_revenue
  end

  test "does not apply coupons to actions" do
    plan = GitHub::Plan.pro

    user = create :credit_card_user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 10)
    user.redeem_coupon(coupon)

    mock_get_usage_breakdown(
      products: create_product_breakdown_array(
        name: "actions",
        skus: [create_skus_breakdown_hash(sku: "linux", estimated_overage_charge: 2400)],
      ),
      times: 2
    )

    pricing = Billing::Pricing.new(account: user, service_remaining: 0.25, include_metered_usage: true)

    create(:billing_budget, owner: pricing.account)
    T.must(pricing.account).reload

    # (6000 minutes used - 3000 included minutes) * $0.008 / minute
    assert_money 24_00, pricing.actions_cost

    # Prorated Cost of Actions Usage without Pro Plan cost due to redeemed Coupon
    assert_money 24_00, pricing.discounted
  end

  test "calculates an annual recurring revenue breakdown" do
    org = create :organization, \
      plan: GitHub::Plan.business,
      seats: 7,
      plan_subscription: create(:billing_plan_subscription)
    Asset::Status.create! owner: org, asset_packs: 3

    listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    create :billing_subscription_item,
      plan_subscription: org.plan_subscription,
      subscribable: listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(account: org)

    # $25/month plan price * 12 months = $300
    assert_money 48_00, pricing.annual_recurring_revenue_details.plan
    # $9/month/seat * 6 additional seats * 12 months = $642
    assert_money 288_00, pricing.annual_recurring_revenue_details.seats
    # $5/month/data pack * 3 data packs * 12 months = $180
    assert_money 180_00, pricing.annual_recurring_revenue_details.data_packs
    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue_details.marketplace

    # $300 plan ARR + $216 seats ARR + $180 data packs ARR = $696
    assert_money 516_00, pricing.annual_recurring_revenue_details.github_total

    # NOTE: doesn't include sponsorship item because its not revenue
    # $300 plan ARR + $216 seats ARR + $180 data packs ARR + $30 marketplace ARR = $726
    assert_money 522_00, pricing.annual_recurring_revenue_details.total
  end

  test "calculates prorated pricing on-the-fly for a user" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    pricing.prorate_to(0.25) do
      assert_money plan.cost_in_cents * 0.25, pricing.discounted
    end

    assert_money plan.cost_in_cents, pricing.discounted
  end

  test "calculates monthly pricing on-the-fly for a user" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: plan,
      plan_duration: "year",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    pricing.monthly do
      assert_money plan.cost_in_cents, pricing.discounted
    end

    assert_money plan.yearly_cost_in_cents, pricing.discounted
  end

  test "calculates yearly pricing on-the-fly for a user" do
    plan = GitHub::Plan.pro
    user = create :user,
      plan: GitHub::Plan.pro,
      plan_duration: "month",
      plan_subscription: create(:billing_plan_subscription)

    pricing = Billing::Pricing.new(account: user)

    pricing.yearly do
      assert_money plan.yearly_cost_in_cents, pricing.discounted
    end

    assert_money plan.cost_in_cents, pricing.discounted
  end

  test "calculates prorated pricing on-the-fly for a business" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    plan = @business.plan
    pricing = Billing::Pricing.new(account: @business)

    pricing.prorate_to(0.25) do
      assert_money plan.cost_in_cents * 0.25 * 100, pricing.discounted
    end

    assert_money plan.cost_in_cents * 100, pricing.discounted
  end

  test "calculates monthly pricing on-the-fly for a business" do
    plan = @business.plan
    pricing = Billing::Pricing.new(account: @business)

    pricing.monthly do
      assert_money plan.cost_in_cents * 100, pricing.discounted
    end

    assert_money plan.yearly_cost_in_cents * 100, pricing.discounted
  end

  test "calculates yearly pricing on-the-fly for a business" do
    @business.update_attribute(:plan_duration, "month")
    @business.reload
    plan = @business.plan
    pricing = Billing::Pricing.new(account: @business)

    pricing.yearly do
      assert_money plan.yearly_cost_in_cents * 100, pricing.discounted
    end

    assert_money plan.cost_in_cents * 100, pricing.discounted
  end

  test "calculates an annual recurring revenue breakdown with a coupon" do
    org = create :organization, \
      plan: GitHub::Plan.business,
      seats: 7,
      plan_subscription: create(:billing_plan_subscription)
    coupon = create(:coupon, discount: 50)
    org.redeem_coupon(coupon)

    Asset::Status.create! owner: org, asset_packs: 3

    listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
    create :billing_subscription_item,
      plan_subscription: org.plan_subscription,
      subscribable: listing_plan,
      quantity: 1

    pricing = Billing::Pricing.new(account: org)

    # 4/month plan price - $4 (of $50) = 0
    assert_money 0, pricing.annual_recurring_revenue_details.plan
    # 4/month/seat price * 6 = 24 -$24 (of $50) = 0
    assert_money 0, pricing.annual_recurring_revenue_details.seats
    # $5/month/data pack * 3 data packs = $15 - $15 (of $50) coupon = $2.07
    assert_money 0, pricing.annual_recurring_revenue_details.data_packs
    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue_details.marketplace
    assert_money 0, pricing.annual_recurring_revenue_details.github_total

    # $10/month * 12 months * 5% marketplace cut = $6
    assert_money 6_00, pricing.annual_recurring_revenue_details.total
  end

  test "calculates pricing for free user with co-pilot trial" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

    create(:billing_subscription_item, :paid,
      plan_subscription: user.plan_subscription,
      subscribable: create(:billing_product_uuid, :copilot),
      free_trial_ends_on: 1.week.from_now
    )

    pricing = Billing::Pricing.new(account: user)

    # $0 while on trial
    assert_money 0, pricing.addons_cost
    assert_money 0, pricing.annual_recurring_revenue
  end

  test "#addon_items ignores in app purchased subscription items" do
    user = create(
      :user,
      plan: GitHub::Plan.free_with_addons,
      plan_subscription: create(:billing_plan_subscription, :zuora)
    )

    create(:billing_subscription_item,
      :paid,
      :iap,
      plan_subscription: user.plan_subscription,
      subscribable: create(:billing_product_uuid, :copilot)
    )

    pricing = Billing::Pricing.new(account: user)

    assert_empty pricing.addon_items
  end

  test "calculates pricing for free user with co-pilot monthly plan" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

    create(:billing_subscription_item, :paid,
      plan_subscription: user.plan_subscription,
      subscribable: create(:billing_product_uuid, :copilot)
    )

    pricing = Billing::Pricing.new(account: user)

    # $10/month for copilot
    assert_money 10_00, pricing.addons_cost
    # $10/month * 12 months = $120
    assert_money 120_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for free user with co-pilot yearly plan" do
    user = create :user,
      plan: GitHub::Plan.free,
      plan_subscription: create(:billing_plan_subscription, :zuora)

    create(:billing_subscription_item, :paid,
      plan_subscription: user.plan_subscription,
      subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :year)
    )

    pricing = Billing::Pricing.new(account: user)

    # $100/year
    assert_money 100_00, pricing.addons_cost
    # $100/year
    assert_money 100_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for yearly pro user with co-pilot monthly plan" do
    pro_user = create(:user, :zuora,
      plan: GitHub::Plan.pro,
      plan_subscription: create(:billing_plan_subscription, :zuora),
      plan_duration: User::BillingDependency::YEARLY_PLAN
    )

    create(:billing_subscription_item, :paid,
      plan_subscription: pro_user.plan_subscription,
      subscribable: create(:billing_product_uuid, :copilot)
    )

    pricing = Billing::Pricing.new(account: pro_user)

    assert_money pro_user.plan.yearly_cost_in_cents, pricing.plan_cost
    # $10/month for copilot
    assert_money 10_00, pricing.addons_cost
    # $10/month * 12 months = $120
    assert_money 120_00, pricing.annual_recurring_revenue_details.addons
    # $48/year for pro + $10/month * 12 months for copilot = $168
    assert_money 168_00, pricing.annual_recurring_revenue
  end

  test "calculates pricing for business with copilot and advanced security trial" do
    business = create(:billing_plan_subscription, :business_owned).business
    owner = business.owners.first
    advanced_security_month_produect_uuid = create(:billing_product_uuid, :advanced_security)

    business.subscribe_to_advanced_security_trial(actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
    pricing = Billing::Pricing.new(account: business)

    # $0 while on trial
    assert_money 0, pricing.addons_cost
  end

  test "calculates pricing for business with copilot and advanced security monthly plan" do
    business = create(:billing_plan_subscription, :business_owned).business
    owner = business.owners.first
    advanced_security_month_produect_uuid = create(:billing_product_uuid, :advanced_security)

    business.subscribe_to_advanced_security(seats: 1, actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
    pricing = Billing::Pricing.new(account: business)

    # $49/month for ghas
    assert_money 49_00, pricing.addons_cost
  end

  test "calculates pricing for business with multiple advanced security monthly seats" do
    business = create(:billing_plan_subscription, :business_owned).business
    owner = business.owners.first
    advanced_security_month_produect_uuid = create(:billing_product_uuid, :advanced_security)

    business.subscribe_to_advanced_security(seats: 10, actor: owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
    pricing = Billing::Pricing.new(account: business)

    # $49/month for ghas * 10 seats
    assert_money 490_00, pricing.addons_cost
  end

  test "calculates pricing for an organization with multiple advanced security monthly seats" do
    organization = create(:credit_card_org, plan: "business_plus")
    user = create :user
    organization.add_admin(user)

    GitHub.flipper[:ghas_self_serve_orgs].enable(organization)

    advanced_security_month_produect_uuid = create(:billing_product_uuid, :advanced_security)

    organization.subscribe_to_advanced_security(seats: 10, actor: user, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
    pricing = Billing::Pricing.new(account: organization)

    # $49/month for ghas * 10 seats
    assert_money 490_00, pricing.addons_cost
  end

  context "subscription changes" do
    test "returns the discounted price when upgrading plans" do
      old_plan = GitHub::Plan.free
      new_plan = GitHub::Plan.pro
      user = create :user,
        plan: old_plan,
        plan_subscription: create(:billing_plan_subscription)

      pricing = Billing::Pricing.new \
        account: user,
        plan: new_plan

      assert_money new_plan.cost_in_cents, pricing.discounted
    end

    test "returns the discounted price when upgrading without a plan subscription" do
      old_plan = GitHub::Plan.free
      new_plan = GitHub::Plan.business
      create(:organization, plan: old_plan)

      pricing = Billing::Pricing.new \
        plan: new_plan,
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
        seats: 5

      assert_money 20_00, pricing.discounted
    end

    test "returns the discounted price when downgrading to free" do
      old_plan = GitHub::Plan.pro
      new_plan = GitHub::Plan.free
      user = create :user,
        plan: old_plan,
        plan_subscription: create(:billing_plan_subscription)

      pricing = Billing::Pricing.new \
        account: user,
        plan: new_plan

      assert_money 0_00, pricing.discounted
    end

    test "returns the discounted price when adding seats" do
      old_seats = 5
      new_seats = 10
      org = create :organization, \
        plan: GitHub::Plan.business_plus,
        seats: old_seats,
        plan_duration: "year",
        plan_subscription: create(:billing_plan_subscription)

      pricing = Billing::Pricing.new \
        account: org,
        seats: new_seats

      # 10 seats at $252 a year = $2,520
      assert_money 2_520_00, pricing.discounted
    end

    test "returns the discounted price when removing seats" do
      old_seats = 10
      new_seats = 8
      org = create :organization, \
        plan: GitHub::Plan.business,
        seats: old_seats,
        plan_subscription: create(:billing_plan_subscription)

      pricing = Billing::Pricing.new \
        account: org,
        seats: new_seats

      # $25 + 7 additional seats at $9 a month = $88
      assert_money 32_00, pricing.discounted
    end

    test "returns the discounted price when removing seats to the base units" do
      old_seats = 10
      new_seats = 5
      org = create :organization, \
        plan: GitHub::Plan.business,
        seats: old_seats,
        plan_subscription: create(:billing_plan_subscription)

      pricing = Billing::Pricing.new \
        account: org,
        seats: new_seats

      assert_money 20_00, pricing.discounted
    end

    test "returns the discounted price when changing from monthly to yearly" do
      old_duration = User::BillingDependency::MONTHLY_PLAN
      new_duration = User::BillingDependency::YEARLY_PLAN
      org = create :organization, \
        plan: GitHub::Plan.business,
        seats: 10,
        plan_duration: old_duration,
        plan_subscription: create(:billing_plan_subscription)
      Asset::Status.create! owner: org, asset_packs: 3
      listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        monthly_price_in_cents: 7_00,
        yearly_price_in_cents: 80_00
      create :billing_subscription_item,
        plan_subscription: org.plan_subscription,
        subscribable: listing_plan,
        quantity: 3

      pricing = Billing::Pricing.new \
        account: org,
        plan_duration: new_duration

      # 9 additional seats at $4 * 12 months = $432 per year
      # 3 data packs at $5 * 12 months       = $180 per year
      # 3 marketplace items at $80           = $240 per year
      # $4 plan * 12 months                 = $48 per year
      # Total                                = $900 per year
      assert_money 48_00, pricing.plan_cost
      assert_money 432_00, pricing.seat_cost
      assert_money 180_00, pricing.data_pack_cost
      assert_money 240_00, pricing.marketplace_item_cost
      assert_money 900_00, pricing.discounted
    end

    test "returns the discounted price when changing from yearly to monthly" do
      old_duration = User::BillingDependency::YEARLY_PLAN
      new_duration = User::BillingDependency::MONTHLY_PLAN
      org = create :organization, \
        plan: GitHub::Plan.business,
        seats: 10,
        plan_duration: old_duration,
        plan_subscription: create(:billing_plan_subscription)
      Asset::Status.create! owner: org, asset_packs: 3
      listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        monthly_price_in_cents: 7_00,
        yearly_price_in_cents: 80_00
      create :billing_subscription_item,
        plan_subscription: org.plan_subscription,
        subscribable: listing_plan,
        quantity: 3

      pricing = Billing::Pricing.new \
        account: org,
        plan_duration: new_duration

      # 9 additional seats at $4   = $36 per month
      # 3 data packs at $5         = $15 per month
      # 3 marketplace items at $7  = $21 per month
      # $45 + $15 + $21 + $25 plan = $106 per month
      assert_money 4_00, pricing.plan_cost
      assert_money 36_00, pricing.seat_cost
      assert_money 15_00, pricing.data_pack_cost
      assert_money 21_00, pricing.marketplace_item_cost
      assert_money 76_00, pricing.discounted
    end

    test "returns the discounted price when adding data packs" do
      old_data_packs = 2
      new_data_packs = 4
      user = create :user,
        plan: GitHub::Plan.free,
        plan_subscription: create(:billing_plan_subscription)
      Asset::Status.create! owner: user, asset_packs: old_data_packs

      pricing = Billing::Pricing.new \
        account: user,
        data_packs: new_data_packs

      # 4 data packs at $5 = $20
      assert_money 20_00, pricing.discounted
    end

    test "returns the discounted price when removing data packs" do
      old_data_packs = 4
      new_data_packs = 2
      user = create :user,
        plan: GitHub::Plan.free,
        plan_subscription: create(:billing_plan_subscription)
      Asset::Status.create! owner: user, asset_packs: old_data_packs

      pricing = Billing::Pricing.new \
        account: user,
        data_packs: new_data_packs

      # 2 data packs at $5 = $10
      assert_money 10_00, pricing.discounted
    end

    test "returns the discounted price when adding a marketplace subscription item" do
      user = create :user,
        plan: GitHub::Plan.free,
        plan_duration: "month",
        plan_subscription: create(:billing_plan_subscription)
      listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
      subscription_item = Billing::SubscriptionItem.new \
        subscribable: listing_plan,
        quantity: 2

      pricing = Billing::Pricing.new \
        account: user,
        subscription_item: subscription_item

      assert_money 20_00, pricing.discounted
    end

    test "returns the discounted price when increasing the quantity of a subscription item" do
      user = create :user,
        plan: GitHub::Plan.free,
        plan_duration: "month",
        plan_subscription: create(:billing_plan_subscription)
      listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
      create :billing_subscription_item,
        plan_subscription: user.plan_subscription,
        subscribable: listing_plan,
        quantity: 2

      new_subscription_item = Billing::SubscriptionItem.new \
        subscribable: listing_plan,
        quantity: 4

      pricing = Billing::Pricing.new \
        account: user,
        subscription_item: new_subscription_item

      assert_money 40_00, pricing.discounted
    end

    test "returns the discounted price when decreasing the quantity of a subscription item" do
      user = create :user,
        plan: GitHub::Plan.free,
        plan_duration: "month",
        plan_subscription: create(:billing_plan_subscription)
      listing_plan = create(:marketplace_listing_plan, :verified_listing, monthly_price_in_cents: 10_00)
      create :billing_subscription_item,
        plan_subscription: user.plan_subscription,
        subscribable: listing_plan,
        quantity: 10

      new_subscription_item = Billing::SubscriptionItem.new \
        subscribable: listing_plan,
        quantity: 5

      pricing = Billing::Pricing.new \
        account: user,
        subscription_item: new_subscription_item

      assert_money 50_00, pricing.discounted
    end

    test "returns the discounted price when changing listing plans on the same listing" do
      user = create :user,
        plan: GitHub::Plan.free,
        plan_duration: "month",
        plan_subscription: create(:billing_plan_subscription)
      listing = create(:marketplace_listing, :verified)
      old_listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        listing: listing,
        monthly_price_in_cents: 10_00
      new_listing_plan = create :marketplace_listing_plan,
        :verified_listing,
        listing: listing,
        monthly_price_in_cents: 15_00
      create :billing_subscription_item,
        plan_subscription: user.plan_subscription,
        subscribable: old_listing_plan,
        quantity: 2

      new_subscription_item = Billing::SubscriptionItem.new \
        subscribable: new_listing_plan,
        quantity: 4

      pricing = Billing::Pricing.new \
        account: user,
        subscription_item: new_subscription_item

      assert_money 60_00, pricing.discounted
    end
  end
end
