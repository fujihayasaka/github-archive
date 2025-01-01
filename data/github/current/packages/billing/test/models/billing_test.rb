# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingModelTest < GitHub::TestCase
  include GitHub::BillingTest

  fixtures do
    @user = create(:user,
      login: "pjhyett",
      plan: "medium",
    )
  end

  test "Billing.today is today in the billing timezone" do
    Time.use_zone "Europe/Amsterdam" do
      Timecop.freeze(Time.zone.local(2014, 3, 1, 2)) do
        assert_equal Date.new(2014, 3, 1), Time.zone.now.to_date
        assert_equal Date.new(2014, 2, 28), GitHub::Billing.today
      end
    end
  end

  test "should allow plan to be string or object" do
    @user.plan = "micro"
    assert_equal "micro", @user.plan.name

    @user.plan = GitHub::Plan.find!("small")
    assert_equal "small", @user.plan.name
  end

  test "a blank plan name should represent the default plan" do
    @user.update_attribute :plan, nil
    assert_equal @user.plan.name, GitHub.default_plan_name

    @user.update_attribute :plan, ""
    assert_equal @user.plan.name, GitHub.default_plan_name
  end

  test "can't set their own duration" do
    @user.plan_duration = "never"
    @user.save
    assert !@user.errors[:plan_duration].blank?
  end

  test "next billing date should never be in the past" do
    Timecop.freeze do
      @user.billed_on = nil
      assert_equal GitHub::Billing.today, @user.next_billing_date
    end

    Timecop.freeze do
      @user.billed_on = GitHub::Billing.today + 5.months
      assert_equal GitHub::Billing.today + 5.months, @user.next_billing_date
    end

    Timecop.freeze do
      @user.billed_on = GitHub::Billing.today - 5.months
      assert_equal GitHub::Billing.today, @user.next_billing_date
    end
  end

  test "finding the next plan for an user" do
    free_user = create(:user, plan: "free")
    micro_user = create(:user, plan: "micro")
    small_user = create(:user, plan: "small")
    medium_user = create(:user, plan: "medium")
    large_user = create(:user, plan: "large")
    mega_user = create(:user, plan: "mega")
    giga_user = create(:user, plan: "giga")

    assert_equal "micro", free_user.next_plan.name
    assert_equal "small", micro_user.next_plan.name
    assert_equal "medium", small_user.next_plan.name
    assert_equal "large", medium_user.next_plan.name
    assert_equal "mega", large_user.next_plan.name
    assert_equal "giga", mega_user.next_plan.name

    assert_nil giga_user.next_plan
    assert_raises(GitHub::Plan::Error) do
      giga_user.next_plan!.name
    end

  end

  test "finds next plan that can handle user's existing private repositories" do
    user = create :user, plan: "small"
    user.plan.repos.times { create(:private_repository, owner: user) }

    user.plan = "free"
    user.reload

    assert_equal "medium", user.next_plan.name
  end

  test "finds the next plan for an organization" do
    free_org        = create(:organization, admin: @user, plan: "free")
    bronze_org      = create(:organization, admin: @user, plan: "bronze")
    silver_org      = create(:organization, admin: @user, plan: "silver")
    gold_org        = create(:organization, admin: @user, plan: "gold")
    platinum_org    = create(:organization, admin: @user, plan: "platinum")
    diamond_org     = create(:organization, admin: @user, plan: "diamond")
    holmium_org     = create(:organization, admin: @user, plan: "holmium")
    fermium_org     = create(:organization, admin: @user, plan: "fermium")
    einsteinium_org = create(:organization, admin: @user, plan: "einsteinium")
    mendelevium_org = create(:organization, admin: @user, plan: "mendelevium")
    curium_org      = create(:organization, admin: @user, plan: "curium")
    californium_org = create(:organization, admin: @user, plan: "californium")
    ytterbium_org   = create(:organization, admin: @user, plan: "ytterbium")
    aluminium_org   = create(:organization, admin: @user, plan: "aluminium")

    # hidden plans
    promethium_org  = create(:organization, admin: @user, plan: "promethium")
    seaborgium_org  = create(:organization, admin: @user, plan: "seaborgium")
    cadmium_org     = create(:organization, admin: @user, plan: "cadmium")
    berkelium_org   = create(:organization, admin: @user, plan: "berkelium")
    thallium_org    = create(:organization, admin: @user, plan: "thallium")
    copernicium_org = create(:organization, admin: @user, plan: "copernicium")
    unlimited_org   = create(:organization, admin: @user, plan: "unlimited")

    # NB: This is because business is cheaper at $4...
    assert_equal "business", free_org.next_plan.name
    assert_equal "silver", bronze_org.next_plan.name
    assert_equal "gold", silver_org.next_plan.name
    assert_equal "platinum", gold_org.next_plan.name
    assert_equal "diamond", platinum_org.next_plan.name
    assert_equal "holmium", diamond_org.next_plan.name
    assert_equal "fermium", holmium_org.next_plan.name
    assert_equal "einsteinium", fermium_org.next_plan.name
    assert_equal "mendelevium", einsteinium_org.next_plan.name
    assert_equal "curium", mendelevium_org.next_plan.name
    assert_equal "californium", curium_org.next_plan.name
    assert_equal "ytterbium", californium_org.next_plan.name
    assert_equal "aluminium", ytterbium_org.next_plan.name
    assert_equal "promethium", aluminium_org.next_plan.name
    assert_equal "seaborgium", promethium_org.next_plan.name
    assert_equal "cadmium", seaborgium_org.next_plan.name

    assert_nil copernicium_org.next_plan

    assert_raises(GitHub::Plan::Error) do
      copernicium_org.next_plan!.name
    end

    assert_nil unlimited_org.next_plan

    assert_raises(GitHub::Plan::Error) do
      unlimited_org.next_plan!.name
    end
  end

  test "knows whether a user needs a card to switch to a plan" do
    user = create :credit_card_user, :with_valid_contact_for_billing

    refute user.needs_valid_payment_method_to_switch_to_plan?("medium")
    refute user.needs_valid_payment_method_to_switch_to_plan?("micro")
    refute user.needs_valid_payment_method_to_switch_to_plan?("large")
    refute user.needs_valid_payment_method_to_switch_to_plan?("free")

    assert create(:user).needs_valid_payment_method_to_switch_to_plan?("large")
    refute create(:user).needs_valid_payment_method_to_switch_to_plan?("free")
  end

  test "knows whether a user needs a card to switch to a plan without billing contact for non commercial flows" do
    user = create :credit_card_user

    refute user.needs_valid_payment_method_to_switch_to_plan?("medium", feature_type: :noncommercial)
    refute user.needs_valid_payment_method_to_switch_to_plan?("micro", feature_type: :noncommercial)
    refute user.needs_valid_payment_method_to_switch_to_plan?("large", feature_type: :noncommercial)
    refute user.needs_valid_payment_method_to_switch_to_plan?("free", feature_type: :noncommercial)

    assert create(:user).needs_valid_payment_method_to_switch_to_plan?("large", feature_type: :noncommercial)
    refute create(:user).needs_valid_payment_method_to_switch_to_plan?("free", feature_type: :noncommercial)
  end

  test "knows a user with an expiring coupon needs a card to switch to a plan" do
    coupon = create(:coupon, discount: "25", duration: "3")
    @user.redeem_coupon(coupon)
    @user.update! billed_on: GitHub::Billing.today + 7.days

    refute @user.needs_valid_payment_method_to_switch_to_plan?("micro")
    assert @user.needs_valid_payment_method_to_switch_to_plan?("large")
  end

  test "payment method not required when adding seats covered by discount" do
    org = create(:organization, plan: GitHub::Plan.business_plus, seats: 1)
    coupon = create :coupon,
      plan: GitHub::Plan.business_plus,
      discount: 105 # 5 seats * $21

    org.redeem_coupon(coupon)

    refute org.needs_valid_payment_method_to_switch_to_plan?(GitHub::Plan.business_plus, 5)
    assert org.needs_valid_payment_method_to_switch_to_plan?(GitHub::Plan.business_plus, 6)
  end

  test "knows that an invoiced user never needs a card" do
    @user.update billing_type: "invoice", plan: "free"
    refute @user.needs_valid_payment_method_to_switch_to_plan? "gold"
  end

  test "knows whether a user needs a card to buy data packs" do
    user = create(:user, plan: "pro")
    user.redeem_coupon create(:coupon, discount: 12)

    refute user.needs_valid_payment_method_to_buy_data_packs?(1), "Coupon should cover data packs"
    assert user.needs_valid_payment_method_to_buy_data_packs?(2), "Coupon should not cover data packs"
  end

  test "knows that an invoiced user doesn't need a card to buy data packs" do
    user = create :user, billing_type: "invoice"
    refute user.needs_valid_payment_method_to_buy_data_packs?(3), "Invoice is a valid way to pay for data packs"
  end
end
