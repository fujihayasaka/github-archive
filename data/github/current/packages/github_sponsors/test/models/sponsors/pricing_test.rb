# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPricingTest < GitHub::TestCase
  extend T::Sig

  skip_unless :sponsors_enabled?

  fixtures do
    @credit_card_user = create(:credit_card_user)
    @yearly_credit_card_user = create(:credit_card_user, plan_duration: "year")
    @credit_card_org = create(:credit_card_org)
    @sponsors_invoiced_org = create(:credit_card_org, :sponsors_invoiced)

    @listing = create(:sponsors_listing, :approved, tier_count: 0)
    @low_recurring_tier = create(:sponsors_tier, :published, :recurring,
      sponsors_listing: @listing,
      monthly_price_in_cents: 1_00,
    )
    @high_recurring_tier = create(:sponsors_tier, :published, :recurring,
      sponsors_listing: @listing,
      monthly_price_in_cents: 10_00,
    )
    @one_time_tier = create(:sponsors_tier, :published, :one_time,
      sponsors_listing: @listing,
      monthly_price_in_cents: 5_00,
    )
  end

  setup do
    @one_time_sponsorship_rows = [
      Sponsors::BulkSponsorshipRow.new(
        sponsorable_login: "foo", amount: "2", is_duplicate: false,
        sponsor: @yearly_credit_card_user, recurring: false
      ),
      Sponsors::BulkSponsorshipRow.new(
        sponsorable_login: "bar", amount: "5", is_duplicate: false,
        sponsor: @yearly_credit_card_user, recurring: false
      )
    ]

    @recurring_sponsorship_rows = [
      Sponsors::BulkSponsorshipRow.new(
        sponsorable_login: "foo", amount: "2", is_duplicate: false,
        sponsor: @credit_card_user, recurring: true
      ),
      Sponsors::BulkSponsorshipRow.new(
        sponsorable_login: "bar", amount: "5", is_duplicate: false,
        sponsor: @credit_card_user, recurring: true
      )
    ]
  end

  context "credit card user" do
    test "no fees for recurring sponsorship" do
      pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_user,
        new_tier: @low_recurring_tier,
      )
      yearly_pricing = Sponsors::Pricing.new(
        sponsor: @yearly_credit_card_user,
        new_tier: @low_recurring_tier,
      )

      assert_equal @low_recurring_tier.to_money, pricing.tier_price
      assert_equal @low_recurring_tier.to_money, pricing.checkout_price
      assert_equal(
        @low_recurring_tier.to_money,
        pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Prorated)
      )
      assert_equal @low_recurring_tier.to_money, pricing.renewal_price

      assert_equal @low_recurring_tier.to_money * 12, yearly_pricing.tier_price
      assert_equal @low_recurring_tier.to_money * 12, yearly_pricing.checkout_price
      assert_equal(
        @low_recurring_tier.to_money * 12,
        yearly_pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Prorated)
      )
      assert_equal @low_recurring_tier.to_money * 12, yearly_pricing.renewal_price
    end

    test "no recurring payment or fees for one-time tier" do
      pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_user,
        new_tier: @one_time_tier,
      )
      yearly_pricing = Sponsors::Pricing.new(
        sponsor: @yearly_credit_card_user,
        new_tier: @one_time_tier,
      )

      assert_equal @one_time_tier.to_money, pricing.tier_price
      assert_equal @one_time_tier.to_money, pricing.checkout_price
      assert_equal(
        @one_time_tier.to_money,
        pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Full)
      )
      assert_equal Billing::Money.zero, pricing.renewal_price

      assert_equal @one_time_tier.to_money, yearly_pricing.tier_price
      assert_equal @one_time_tier.to_money, yearly_pricing.checkout_price
      assert_equal(
        @one_time_tier.to_money,
        yearly_pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Full)
      )
      assert_equal Billing::Money.zero, yearly_pricing.renewal_price
    end

    test "no intial payment for mid-cycle downgrade" do
      mid_cycle(sponsor: @credit_card_user, tier: @high_recurring_tier) do |sponsorship|
        pricing = Sponsors::Pricing.new(
          sponsor: @credit_card_user,
          new_tier: @low_recurring_tier,
          current_tier: sponsorship.tier,
        )

        expected_checkout_price = Billing::Money.zero

        assert_equal @low_recurring_tier.to_money, pricing.tier_price
        assert_equal expected_checkout_price, pricing.checkout_price
        assert_equal(
          expected_checkout_price,
          pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Delayed)
        )
        assert_equal @low_recurring_tier.to_money, pricing.renewal_price
      end
    end

    test "mid-cycle new sponsorship supports full payment" do
      mid_cycle(sponsor: @credit_card_user, tier: @one_time_tier) do
        pricing = Sponsors::Pricing.new(
          sponsor: @credit_card_user,
          new_tier: @low_recurring_tier,
        )

        expected_prorated_price = Billing::Money.new(30)

        assert_equal @low_recurring_tier.to_money, pricing.tier_price
        assert_equal(
          @low_recurring_tier.to_money,
          pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Full)
        )
        assert_equal expected_prorated_price, pricing.checkout_price
        assert_equal @low_recurring_tier.to_money, pricing.renewal_price
        assert_same_elements(
          [
            Sponsors::Pricing::PaymentOption::Prorated,
            Sponsors::Pricing::PaymentOption::Full,
          ],
          pricing.available_payment_options
        )
      end
    end

    test "mid-cycle requires existing sponsors-purpose Zuora subscription for full payment" do
      mid_cycle(sponsor: @credit_card_user) do
        pricing = Sponsors::Pricing.new(
          sponsor: @credit_card_user,
          new_tier: @low_recurring_tier,
        )

        assert_nil @credit_card_user.sponsors_plan_subscription

        assert_equal([Sponsors::Pricing::PaymentOption::Prorated], pricing.available_payment_options)
      end
    end

    test "mid-cycle upgrade is prorated" do
      mid_cycle(sponsor: @credit_card_user, tier: @low_recurring_tier) do |sponsorship|
        pricing = Sponsors::Pricing.new(
          sponsor: @credit_card_user,
          new_tier: @high_recurring_tier,
          current_tier: sponsorship.tier,
        )

        expected_price = Billing::Money.new(2_70)

        assert_equal expected_price, pricing.checkout_price
        assert_equal(
          expected_price,
          pricing.checkout_price(payment_option: Sponsors::Pricing::PaymentOption::Prorated)
        )
        assert_equal @high_recurring_tier.to_money, pricing.renewal_price
      end
    end
  end

  context "credit card org" do
    test "includes service and transactions fees" do
      recurring_pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_org,
        new_tier: @low_recurring_tier,
      )
      one_time_pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_org,
        new_tier: @one_time_tier,
      )

      expected_renewal_fee_price = Billing::Money.new(6)
      expected_one_time_fee_price = Billing::Money.new(30)

      assert_equal(@low_recurring_tier.to_money, recurring_pricing.tier_net_price)
      assert_equal(@low_recurring_tier.to_money + expected_renewal_fee_price, recurring_pricing.tier_price)
      assert_equal(@low_recurring_tier.to_money + expected_renewal_fee_price, recurring_pricing.checkout_price)
      assert_equal(@low_recurring_tier.to_money + expected_renewal_fee_price, recurring_pricing.renewal_price)

      assert_equal(@one_time_tier.to_money, one_time_pricing.tier_net_price)
      assert_equal(@one_time_tier.to_money + expected_one_time_fee_price, one_time_pricing.tier_price)
      assert_equal(@one_time_tier.to_money + expected_one_time_fee_price, one_time_pricing.checkout_price)
      assert_equal(Billing::Money.zero, one_time_pricing.renewal_price)
    end
  end

  context "Sponsors-invoiced org" do
    test "does not include service fee in checkout price since paid during invoicing" do
      recurring_pricing = Sponsors::Pricing.new(
        sponsor: @sponsors_invoiced_org,
        new_tier: @low_recurring_tier,
      )
      one_time_pricing = Sponsors::Pricing.new(
        sponsor: @sponsors_invoiced_org,
        new_tier: @one_time_tier,
      )

      expected_renewal_fee_price = Billing::Money.zero
      expected_one_time_fee_price = Billing::Money.zero

      assert_equal(@low_recurring_tier.to_money, recurring_pricing.tier_net_price)
      assert_equal(@low_recurring_tier.to_money + expected_renewal_fee_price, recurring_pricing.tier_price)
      assert_equal(@low_recurring_tier.to_money + expected_renewal_fee_price, recurring_pricing.checkout_price)
      assert_equal(@low_recurring_tier.to_money + expected_renewal_fee_price, recurring_pricing.renewal_price)

      assert_equal(@one_time_tier.to_money, one_time_pricing.tier_net_price)
      assert_equal(@one_time_tier.to_money + expected_one_time_fee_price, one_time_pricing.tier_price)
      assert_equal(@one_time_tier.to_money + expected_one_time_fee_price, one_time_pricing.checkout_price)
      assert_equal(Billing::Money.zero, one_time_pricing.renewal_price)
    end

    test "supports delayed payment" do
      mid_cycle(sponsor: @sponsors_invoiced_org, tier: @one_time_tier) do
        pricing = Sponsors::Pricing.new(
          sponsor: @sponsors_invoiced_org,
          new_tier: @low_recurring_tier,
        )

        assert_same_elements(
          [
            Sponsors::Pricing::PaymentOption::Prorated,
            Sponsors::Pricing::PaymentOption::Full,
            Sponsors::Pricing::PaymentOption::Delayed,
          ],
          pricing.available_payment_options
        )
      end
    end
  end

  context "#checkout_sponsors_invoiced_fee_price" do
    test "supports discovering possible savings" do
      sponsors_invoiced_pricing = Sponsors::Pricing.new(
        sponsor: @sponsors_invoiced_org,
        new_tier: @low_recurring_tier,
      )
      credit_card_org_pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_org,
        new_tier: @low_recurring_tier,
      )
      user_pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_user,
        new_tier: @low_recurring_tier,
      )

      assert_equal(Billing::Money.zero, sponsors_invoiced_pricing.checkout_sponsors_invoiced_savings)
      assert_equal(Billing::Money.zero, user_pricing.checkout_sponsors_invoiced_savings)
      assert_equal(Billing::Money.new(3), credit_card_org_pricing.checkout_sponsors_invoiced_savings)
    end
  end

  context "bulk sponsorship rows" do
    test "calculates price for credit-card org making one-time bulk sponsorships" do
      pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_org,
        new_tier: nil,
        bulk_sponsorship_rows: @one_time_sponsorship_rows,
      )

      expected_net_amount = 7.to_money
      expected_amount_with_fee = expected_net_amount * 1.06
      expected_renewal_amount_with_fee = 0.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_amount_with_fee, pricing.checkout_price
      assert_equal expected_renewal_amount_with_fee, pricing.renewal_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Full], pricing.available_payment_options
    end

    test "calculates price for credit-card org making recurring bulk sponsorships on billing date" do
      pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_org,
        new_tier: nil,
        bulk_sponsorship_rows: @recurring_sponsorship_rows,
      )

      expected_net_amount = 7.to_money
      expected_amount_with_fee = expected_net_amount * 1.06

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_amount_with_fee, pricing.checkout_price
      assert_equal expected_amount_with_fee, pricing.renewal_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Prorated], pricing.available_payment_options
    end

    test "calculates price for credit-card org making recurring bulk sponsorships mid-cycle" do
      mid_cycle(sponsor: @credit_card_org) do
        pricing = Sponsors::Pricing.new(
          sponsor: @credit_card_org,
          new_tier: nil,
          bulk_sponsorship_rows: @recurring_sponsorship_rows,
        )

        expected_net_amount = (7 * 0.3).to_money
        expected_amount_with_fee = expected_net_amount * 1.06
        expected_renewal_amount_with_fee = (7 * 1.06).to_money

        assert_equal expected_net_amount, pricing.checkout_net_price
        assert_equal expected_amount_with_fee, pricing.checkout_price
        assert_equal expected_renewal_amount_with_fee, pricing.renewal_price

        assert_same_elements [Sponsors::Pricing::PaymentOption::Prorated], pricing.available_payment_options
      end
    end

    test "calculates price for user making one-time bulk sponsorships" do
      pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_user,
        new_tier: nil,
        bulk_sponsorship_rows: @one_time_sponsorship_rows,
      )

      expected_net_amount = 7.to_money
      expected_renewal_amount_with_fee = 0.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_net_amount, pricing.checkout_price
      assert_equal expected_renewal_amount_with_fee, pricing.renewal_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Full], pricing.available_payment_options
    end

    test "calculates price for user making recurring bulk sponsorships on billing date" do
      pricing = Sponsors::Pricing.new(
        sponsor: @credit_card_user,
        new_tier: nil,
        bulk_sponsorship_rows: @recurring_sponsorship_rows,
      )

      expected_net_amount = 7.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_net_amount, pricing.checkout_price
      assert_equal expected_net_amount, pricing.renewal_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Prorated], pricing.available_payment_options
    end

    test "calculates price for user making recurring bulk sponsorships mid-cycle" do
      mid_cycle(sponsor: @credit_card_user) do
        pricing = Sponsors::Pricing.new(
          sponsor: @credit_card_user,
          new_tier: nil,
          bulk_sponsorship_rows: @recurring_sponsorship_rows,
        )

        expected_net_amount = (7 * 0.3).to_money
        expected_renewal_amount = 7.to_money

        assert_equal expected_net_amount, pricing.checkout_net_price
        assert_equal expected_net_amount, pricing.checkout_price
        assert_equal expected_renewal_amount, pricing.renewal_price

        assert_same_elements [Sponsors::Pricing::PaymentOption::Prorated], pricing.available_payment_options
      end
    end

    test "calculates price for invoiced org making one-time bulk sponsorships" do
      pricing = Sponsors::Pricing.new(
        sponsor: @sponsors_invoiced_org,
        new_tier: nil,
        bulk_sponsorship_rows: @one_time_sponsorship_rows,
      )

      expected_net_amount = 7.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_net_amount, pricing.checkout_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Full], pricing.available_payment_options
    end

    test "calculates price for invoiced org making recurring bulk sponsorships on billing date" do
      pricing = Sponsors::Pricing.new(
        sponsor: @sponsors_invoiced_org,
        new_tier: nil,
        bulk_sponsorship_rows: @recurring_sponsorship_rows,
      )

      expected_net_amount = 7.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_net_amount, pricing.checkout_price

      assert_same_elements([
          Sponsors::Pricing::PaymentOption::Prorated,
          Sponsors::Pricing::PaymentOption::Delayed
        ],
        pricing.available_payment_options
      )
    end

    test "calculates price for invoiced org making recurring bulk sponsorships mid-cycle" do
      mid_cycle(sponsor: @credit_card_org) do
        pricing = Sponsors::Pricing.new(
          sponsor: @sponsors_invoiced_org,
          new_tier: nil,
          bulk_sponsorship_rows: @recurring_sponsorship_rows,
        )

        expected_net_amount = 7.to_money

        assert_equal expected_net_amount, pricing.checkout_net_price
        assert_equal expected_net_amount, pricing.checkout_price

        assert_same_elements([
            Sponsors::Pricing::PaymentOption::Prorated,
            Sponsors::Pricing::PaymentOption::Delayed
          ],
          pricing.available_payment_options
        )
      end
    end

    test "calculates price for user with yearly plan duration making one-time bulk sponsorships" do
      pricing = Sponsors::Pricing.new(
        sponsor: @yearly_credit_card_user,
        new_tier: nil,
        bulk_sponsorship_rows: @one_time_sponsorship_rows,
      )

      expected_net_amount = 7.to_money
      expected_renewal_amount_with_fee = 0.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_net_amount, pricing.checkout_price
      assert_equal expected_renewal_amount_with_fee, pricing.renewal_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Full], pricing.available_payment_options
    end

    test "calculates price for user with yearly plan duration making recurring bulk sponsorships" do
      pricing = Sponsors::Pricing.new(
        sponsor: @yearly_credit_card_user,
        new_tier: nil,
        bulk_sponsorship_rows: @recurring_sponsorship_rows,
      )

      expected_net_amount = 84.to_money

      assert_equal expected_net_amount, pricing.checkout_net_price
      assert_equal expected_net_amount, pricing.checkout_price
      assert_equal expected_net_amount, pricing.renewal_price

      assert_same_elements [Sponsors::Pricing::PaymentOption::Prorated], pricing.available_payment_options
    end
  end

  sig do
    params(
      sponsor: T.any(User, Organization),
      tier: T.nilable(SponsorsTier),
    ).void
  end
  def mid_cycle(sponsor:, tier: nil)
    raise "Block required" unless block_given?

    travel_to(GitHub::Billing.timezone.local(2023, 9, 19, 8, 0, 0)) do
      sponsor.update!(billed_on: GitHub::Billing.today + 10.days)
      create(:billing_plan_subscription, :zuora, user: sponsor)
      T.must(sponsor.customer).update!(bill_cycle_day: 29)
      sponsorship = if tier.present?
        sponsorship = create(:sponsorship, sponsor: sponsor, tier: tier)
        customer = T.must(sponsor.customer_for(:sponsors) || sponsor.customer_for(:general))
        # fake Zuora account setup
        customer.update!(bill_cycle_day: 29)
        T.must(sponsor.sponsors_plan_subscription).update!(
          zuora_subscription_id: SecureRandom.hex(16),
          zuora_subscription_number: "A-S#{SecureRandom.hex(6)}",
        )
        sponsor.reload
        sponsorship
      end

      sponsor.reload
      yield(sponsorship)
    end
  end
end
