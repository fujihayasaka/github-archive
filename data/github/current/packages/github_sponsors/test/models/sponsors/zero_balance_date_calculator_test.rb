# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsZeroBalanceDateCalculatorTest < GitHub::TestCase
  fixtures do
    @sponsorship1 = create(:sponsorship, :sponsors_invoiced, monthly_price_in_cents: 50_00, expires_at: nil)
    @sponsorship2 = create(:sponsorship, :sponsors_invoiced, monthly_price_in_cents: 50_00, expires_at: nil)
    @customer = @sponsorship1.sponsor.sponsors_customer
  end

  setup do
    @balance = Billing::Money.new(300_00)
  end

  context "#calculable?" do
    test "returns false when there are no sponsorships" do
      calculator = Sponsors::ZeroBalanceDateCalculator.new(
        sponsorships: [],
        current_balance: @balance,
        customer: @customer
      )

      refute_predicate calculator, :calculable?
    end

    test "returns false when the sponsor will not run out of funds within a year" do
      calculator = Sponsors::ZeroBalanceDateCalculator.new(
        sponsorships: [@sponsorship1],
        current_balance: Billing::Money.new(700_00),
        customer: @customer
      )

      refute_predicate calculator, :calculable?
    end

    test "returns true with valid sponsorships" do
      calculator = Sponsors::ZeroBalanceDateCalculator.new(
        sponsorships: [@sponsorship1],
        current_balance: @balance,
        customer: @customer
      )

      assert_predicate calculator, :calculable?
    end
  end

  context "#zero_balance_date" do
    test "returns nil if the date is not calculable" do
      calculator = Sponsors::ZeroBalanceDateCalculator.new(
        sponsorships: [],
        current_balance: @balance,
        customer: @customer
      )

      assert_nil calculator.zero_balance_date, :zero_balance_date
    end

    test "returns the date of the last payment that will be fully covered by the sponsor's balance" do
      today = Time.parse("2022-01-01")
      expected_date = Date.new(2022, 3, 15)
      @customer.update!(bill_cycle_day: 15)

      travel_to(today) do
        calculator = Sponsors::ZeroBalanceDateCalculator.new(
          sponsorships: [@sponsorship1, @sponsorship2],
          current_balance: @balance,
          customer: @customer
        )
        calculator.zero_balance_date

        assert_equal expected_date, calculator.zero_balance_date
      end
    end

    test "correctly rounds to the last valid date of the month when the billing day is not valid for the month" do
      today = Time.parse("2022-01-01")
      expected_date = Date.new(2022, 2, 28)
      @customer.update!(bill_cycle_day: 31)

      travel_to(today) do
        calculator = Sponsors::ZeroBalanceDateCalculator.new(
          sponsorships: [@sponsorship1],
          current_balance: Billing::Money.new(100_00),
          customer: @customer
        )
        calculator.zero_balance_date

        assert_equal expected_date, calculator.zero_balance_date
      end
    end

    test "returns the date of the previous billing cycle if only some commitments can be paid for a given month" do
      today = Time.parse("2022-01-01")
      expected_date = Date.new(2022, 1, 15)
      @customer.update!(bill_cycle_day: 15)

      travel_to(today) do
        calculator = Sponsors::ZeroBalanceDateCalculator.new(
          sponsorships: [@sponsorship1, @sponsorship2],
          current_balance: Billing::Money.new(150_00),
          customer: @customer
        )
        calculator.zero_balance_date

        assert_equal expected_date, calculator.zero_balance_date
      end
    end

    test "calculates assuming the bill_cycle_day is 1 if the customer's bill_cycle_day is 0" do
      today = Time.parse("2022-01-01")
      expected_date = Date.new(2022, 4, 1)
      @customer.update!(bill_cycle_day: 0)

      travel_to(today) do
        calculator = Sponsors::ZeroBalanceDateCalculator.new(
          sponsorships: [@sponsorship1, @sponsorship2],
          current_balance: Billing::Money.new(300_00),
          customer: @customer
        )
        calculator.zero_balance_date

        assert_equal expected_date, calculator.zero_balance_date
      end

    end
  end

  context "#remaining_balance" do
    test "returns how much money is left over after as many commitments as possible have been covered" do
      today = Time.parse("2022-01-01")

      travel_to(today) do
        calculator = Sponsors::ZeroBalanceDateCalculator.new(
          sponsorships: [@sponsorship1],
          current_balance: Billing::Money.new(75_00),
          customer: @customer
        )

        assert_equal 2500, calculator.remaining_balance
      end
    end

    test "returns the current balance if the sponsor cannot afford the current month's sponsorships" do
      today = Time.parse("2022-01-01")
      low_balance = Billing::Money.new(15_00)
      @customer.update!(bill_cycle_day: 12)
      @customer.reload

      travel_to(today) do
        calculator = Sponsors::ZeroBalanceDateCalculator.new(
          sponsorships: [@sponsorship1],
          current_balance: low_balance,
          customer: @customer
        )

        assert_equal low_balance.cents, calculator.remaining_balance
      end
    end
  end
end
