# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsTierPriceTest < GitHub::TestCase
  fixtures do
    @recurring_tier = create(:sponsors_tier, :published, :recurring)
    @one_time_tier = create(:sponsors_tier, :published, :one_time)
    @sponsor = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)
    @cc_org_sponsor = create(:credit_card_org)
  end

  test "returns positive number when no sponsorship currently exists" do
    price = Sponsors::TierPrice.call(
      sponsor: @sponsor,
      new_tier: @recurring_tier,
    )

    assert_operator price, :<=, @recurring_tier.base_price(duration: :month),
      "charge shouldn't be more than the selected tier"
    assert_operator price, :>, Billing::Money.zero
  end

  test "returns full amount with fee when no sponsorship exists for cc org and prorated is false" do
    price = Sponsors::TierPrice.call(
      sponsor: @cc_org_sponsor,
      new_tier: @recurring_tier,
      prorated: false,
    )

    assert_equal price, @recurring_tier.base_price_with_fee(sponsor: @cc_org_sponsor),
      "non-prorated price should be the same as the base price with fee"
  end

  test "excludes fee for cc_orgs when exclude_fees is true" do
    price = Sponsors::TierPrice.call(
      sponsor: @cc_org_sponsor,
      new_tier: @recurring_tier,
      prorated: false,
      exclude_fees: true,
    )

    assert_equal price, @recurring_tier.base_price(duration: :month),
      "non-prorated price should be the same as the base price when fee is excluded"
  end

  test "does not add fees for users" do
    price = Sponsors::TierPrice.call(
      sponsor: @sponsor,
      new_tier: @recurring_tier,
      prorated: false,
    )

    assert_equal price, @recurring_tier.base_price(duration: :month),
      "non-prorated price should be the same as the base price"
  end

  test "does not add fees for invoiced orgs" do
    invoiced_org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)

    price = Sponsors::TierPrice.call(
      sponsor: @sponsor,
      new_tier: @recurring_tier,
      prorated: false,
    )

    assert_equal price, @recurring_tier.base_price(duration: :month),
      "non-prorated price should be the same as the base price"
  end

  test "returns full amount when no sponsorship currently exists and prorated is false" do
    price = Sponsors::TierPrice.call(
      sponsor: @sponsor,
      new_tier: @recurring_tier,
      prorated: false,
    )

    assert_equal price, @recurring_tier.base_price(duration: :month),
      "non-prorated price should be the same as the base price"
  end

  test "returns positive number when no sponsorship currently exists and unsaved custom tier is selected" do
    custom_tier = build(:sponsors_tier, :custom, creator: @sponsor)

    price = Sponsors::TierPrice.call(
      sponsor: @sponsor,
      new_tier: custom_tier,
    )

    assert_operator price, :<=, custom_tier.base_price(duration: :month),
      "charge shouldn't be more than the selected tier"
    assert_operator price, :>, 0
  end

  test "does not error when there is no plan subscription" do
    user = create(:user)

    price = Sponsors::TierPrice.call(
      sponsor: user,
      new_tier: @recurring_tier
    )

    assert_equal @recurring_tier.base_price, price
  end

  test "adding a sponsorship mid-cycle prorates the cost" do
    Timecop.freeze(GitHub::Billing.timezone.local(2022, 9, 19, 8, 0, 0)) do
      user = create :user, plan: "free_with_addons", billed_on: GitHub::Billing.today + 10.days

      price = Sponsors::TierPrice.call(
        sponsor: user,
        new_tier: @recurring_tier
      )

      assert_equal Billing::Money.new(30), price
    end
  end

  test "upgrading a sponsorship mid-cycle prorates the cost" do
    Timecop.freeze(GitHub::Billing.timezone.local(2022, 9, 19, 8, 0, 0)) do
      user = create :user, plan: "free_with_addons", billed_on: GitHub::Billing.today + 10.days
      new_tier = create(:sponsors_tier, :published, :recurring,
        sponsors_listing: @recurring_tier.sponsors_listing,
      )
      price_difference = new_tier.base_price(duration: :month) - @recurring_tier.base_price(duration: :month)

      price = Sponsors::TierPrice.call(
        sponsor: user,
        new_tier: new_tier,
        current_tier: @recurring_tier,
      )

      assert_operator price, :<=, price_difference,
        "charge shouldn't be more than the price difference"
      assert_operator price, :>, Billing::Money.zero
    end
  end

  test "downgrading a sponsorship returns Billing::Money.zero" do
    Timecop.freeze(GitHub::Billing.timezone.local(2022, 9, 19, 8, 0, 0)) do
      user = create :user, plan: "free_with_addons", billed_on: GitHub::Billing.today + 10.days
      current_tier = create(:sponsors_tier, :published, :recurring,
        sponsors_listing: @recurring_tier.sponsors_listing
      )
      price_difference = current_tier

      [true, false].each do |prorated|
        price = Sponsors::TierPrice.call(
          sponsor: user,
          new_tier: @recurring_tier,
          current_tier: current_tier,
          prorated: prorated,
        )

        assert_equal Billing::Money.zero, price
      end
    end
  end

  test "adding a Zuora-invoiced sponsorship mid-cycle prorates the cost based on the Sponsors-purpose billing date" do
    Timecop.freeze(GitHub::Billing.timezone.local(2022, 9, 19, 8, 0, 0)) do
      org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
        billed_on: GitHub::Billing.today + 10.days,
      )
      org.sponsors_customer.update_columns(bill_cycle_day: (GitHub::Billing.today + 20.days).day)

      price = Sponsors::TierPrice.call(
        sponsor: org,
        new_tier: @recurring_tier
      )

      assert_equal Billing::Money.new(63), price
    end
  end

  # https://github.com/github/sponsors/issues/3484
  test "does not include non-Sponsors items in the price" do
    Timecop.freeze(GitHub::Billing.timezone.local(2022, 9, 19, 8, 0, 0)) do
      org = create(:business_plus_org)

      price = Sponsors::TierPrice.call(
        sponsor: org,
        new_tier: @recurring_tier,
      )

      assert_operator price, :<=, @recurring_tier.base_price_with_fee(sponsor: org),
        "charge shouldn't be more than the selected tier, plus fee when feature enabled"
      assert_operator price, :>, 0
    end
  end

  test "one-time tier is full price regardless of proration" do
    [true, false].each do |prorated|
      price = Sponsors::TierPrice.call(
        sponsor: @sponsor,
        new_tier: @one_time_tier,
        prorated: prorated,
      )

      assert_equal @one_time_tier.base_price(duration: :month), price
    end
  end

  test "one-time tier is full price regardless of existing sponsorship" do
    current_tier = create(:sponsors_tier, :published, :recurring,
      sponsors_listing: @one_time_tier.sponsors_listing,
    )
    [true, false].each do |prorated|
      price = Sponsors::TierPrice.call(
        sponsor: @sponsor,
        new_tier: @one_time_tier,
        current_tier: current_tier,
        prorated: prorated,
      )

      assert_equal @one_time_tier.base_price(duration: :month), price
    end
  end

  test "recurring tier pricing is the same whether a one-time current tier exists or not" do
    Timecop.freeze(GitHub::Billing.timezone.local(2022, 9, 19, 8, 0, 0)) do
      one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: @recurring_tier.sponsors_listing,
      )

      [true, false].each do |prorated|
        price_without_current_tier = Sponsors::TierPrice.call(
          sponsor: @sponsor,
          new_tier: @recurring_tier,
          prorated: prorated,
        )

        price_with_current_one_time_tier = Sponsors::TierPrice.call(
          sponsor: @sponsor,
          new_tier: @recurring_tier,
          current_tier: one_time_tier,
          prorated: prorated,
        )

        assert_equal price_without_current_tier, price_with_current_one_time_tier
      end
    end
  end

  test "raises an ListingMismatchError if current and new tiers are for different listings" do
    other_listing_tier = create(:sponsors_tier, :published, :recurring)

    assert_raises Sponsors::TierPrice::ListingMismatchError do
      Sponsors::TierPrice.call(
        sponsor: @sponsor,
        new_tier: @recurring_tier,
        current_tier: other_listing_tier
      )
    end
  end
end if GitHub.sponsors_enabled?
