# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsSponsorshipCommitmentTest < GitHub::TestCase
  fixtures do
    @sponsorships = create_list(:sponsorship, 2, monthly_price_in_cents: 5000)
  end

  context "#price_in_cents" do
    test "adds the total price of all the sponsorships for a given month" do
      freeze_time do
        commitment = Sponsors::SponsorshipCommitment.new(
          months_from_now: 1, sponsorships: @sponsorships, bill_cycle_day: 1
        )

        assert_equal 10000, commitment.price_in_cents
      end
    end

    test "does not include the price of sponsorships that expire before the given month" do
      expired_sponsorship = create(:sponsorship, monthly_price_in_cents: 5000, expires_at: Date.new(2022, 1, 1))

      freeze_time do
        commitment = Sponsors::SponsorshipCommitment.new(
          months_from_now: 1, sponsorships: @sponsorships.concat([expired_sponsorship]), bill_cycle_day: 1
        )

        assert_equal 10000, commitment.price_in_cents
      end
    end

    test "returns 0 for the current month if the billing date has passed" do
      bill_cycle_day = 1
      non_bill_cycle_date = GitHub::Billing.timezone.local(2022, 1, 31)

      travel_to non_bill_cycle_date do
        commitment = Sponsors::SponsorshipCommitment.new(
          months_from_now: 0, sponsorships: @sponsorships, bill_cycle_day: bill_cycle_day
        )

        assert_equal 0, commitment.price_in_cents
      end
    end

    test "adds the total price for a future month if the billing date is the same as bill cycle day" do
      bill_cycle_day = 1
      bill_cycle_date = GitHub::Billing.timezone.local(2022, 1, 1)

      travel_to bill_cycle_date do
        commitment = Sponsors::SponsorshipCommitment.new(
          months_from_now: 1, sponsorships: @sponsorships, bill_cycle_day: bill_cycle_day
        )

        assert_equal 10000, commitment.price_in_cents
      end
    end

    test "does not add to the total price if the sponsorship has already been paid" do
      bill_cycle_day = 12
      bill_cycle_date = GitHub::Billing.timezone.local(2022, 1, 12)

      travel_to bill_cycle_date do
        commitment = Sponsors::SponsorshipCommitment.new(
          months_from_now: 0, sponsorships: @sponsorships, bill_cycle_day: bill_cycle_day
        )

        assert_equal 0, commitment.price_in_cents
      end
    end

    test "includes the price of sponsorships that will expire in the future" do
      today = Date.current
      sponsorship_with_expiration = create(:sponsorship, monthly_price_in_cents: 5000, expires_at: today + 2.months)

      travel_to today do
        commitment = Sponsors::SponsorshipCommitment.new(
          months_from_now: 0,
          sponsorships: @sponsorships.concat([sponsorship_with_expiration]),
          bill_cycle_day: today + 1.day
        )

        assert_equal 15000, commitment.price_in_cents
      end
    end
  end
end
