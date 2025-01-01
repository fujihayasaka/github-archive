# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Sponsors::Invoiced::SponsorshipFormInputsTest < GitHub::TestCase
  test "input defaults" do
    inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new

    assert_nil inputs.sponsorship_id
    assert_nil inputs.sponsorable_login
    assert_nil inputs.amount_in_dollars
    assert_predicate inputs, :is_recurring
    assert_nil inputs.end_month
    assert_nil inputs.end_year
    assert_predicate inputs, :is_public
    refute_predicate inputs, :email_opt_in
  end

  context ".from_sponsorship" do
    test "inputs from existing recurring sponsorship" do
      end_date = 2.months.from_now
      recurring_sponsorship = create(:sponsorship, expires_at: end_date)
      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.from_sponsorship(recurring_sponsorship)

      assert_equal inputs.sponsorship_id, recurring_sponsorship.id
      assert_equal inputs.sponsorable_login, recurring_sponsorship.sponsorable_login
      assert_equal inputs.amount_in_dollars, recurring_sponsorship.monthly_price_in_dollars.to_i
      assert_equal inputs.is_recurring, recurring_sponsorship.recurring_payment?
      assert_equal inputs.end_month, recurring_sponsorship.expires_at.month
      assert_equal inputs.end_year, recurring_sponsorship.expires_at.year
      assert_equal inputs.is_public, recurring_sponsorship.privacy_public?
      assert_equal inputs.email_opt_in, recurring_sponsorship.is_sponsor_opted_in_to_email?
    end

    test "inputs from existing one-time sponsorship" do
      one_time_sponsorship = create(:sponsorship, :one_time, :private, :email_opted_out)
      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.from_sponsorship(one_time_sponsorship)

      assert_equal inputs.sponsorship_id, one_time_sponsorship.id
      assert_equal inputs.sponsorable_login, one_time_sponsorship.sponsorable_login
      assert_equal inputs.amount_in_dollars, one_time_sponsorship.monthly_price_in_dollars.to_i
      assert_equal inputs.is_recurring, one_time_sponsorship.recurring_payment?
      assert_nil inputs.end_date
      assert_equal inputs.is_public, one_time_sponsorship.privacy_public?
      assert_equal inputs.email_opt_in, one_time_sponsorship.is_sponsor_opted_in_to_email?
    end
  end

  context "#sponsorable" do
    test "returns the sponsorable" do
      sponsorable = create(:user, :sponsorable)
      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new(
        sponsorable_login: sponsorable.login
      )

      assert_equal sponsorable, inputs.sponsorable
    end
  end

  context "#sponsors_listing" do
    test "returns the sponsors listing" do
      sponsorable = create(:user, :sponsorable)
      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new(
        sponsorable_login: sponsorable.login
      )

      assert_equal sponsorable.sponsors_listing, inputs.sponsors_listing
    end
  end

  context "#end_date" do
    test "returns the end date as the end of the selected month" do
      end_date = 2.months.from_now
      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new(
        end_month: end_date.month,
        end_year: end_date.year
      )

      assert_equal end_date.end_of_month.to_date, inputs.end_date
    end
  end

  context "#parent_tier_id" do
    test "returns the id of the closest less expensive tier" do
      tier = create(:sponsors_tier, :published)
      sponsorable = tier.sponsorable

      inputs = Stafftools::Sponsors::Invoiced::SponsorshipFormInputs.new(
        sponsorable_login: sponsorable.login,
        amount_in_dollars: tier.monthly_price_in_dollars + 1,
        is_recurring: tier.recurring?,
      )

      assert_equal tier.id, inputs.parent_tier_id
    end
  end
end
