# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::ReceiptTest < GitHub::TestCase
  include GitHub::Billing::CurrencyTestHelper

  fixtures do
    @sponsorable = create(:user, :sponsorable)
    @listing = @sponsorable.sponsors_listing
    @stripe_account = create(:stripe_connect_account, sponsors_listing: @listing)

    @other_sponsorable = create(:organization, :sponsorable)
    @other_listing = @other_sponsorable.sponsors_listing
    @other_stripe_account = create(:stripe_connect_account, sponsors_listing: @other_listing)

    @fiscal_host_listing = create(:sponsors_listing, :fiscal_host, :with_stripe_account)
    @fiscal_host = @fiscal_host_listing.sponsorable
    @fiscal_host_stripe = @fiscal_host_listing.active_stripe_connect_account
    @child_listing = create(:sponsors_listing, :with_fiscal_host,
      parent_listing: @fiscal_host_listing)
  end

  setup do
    skip unless GitHub.sponsors_enabled?

    setup_currency_exchange

    @tax_id = "abc123"
    @start_date = Time.at(1613869312).utc.to_datetime
    @stripe_payout = Billing::Stripe::Payout.new(
      stripe_payout: Stripe::Payout.construct_from(
        id: "po_8675309",
        amount: 5_00,
        currency: "gbp",
        created: 1616288570,
      ),
      stripe_account_id: "acct_123abc",
    )
    @receipt = SponsorsListing::Receipt.for_payout(sponsors_listing: @listing, stripe_payout: @stripe_payout,
      tax_id: @tax_id, start_date: @start_date)
  end

  context ".for_payout" do
    test "returns a receipt set up for the given Stripe::Payout" do
      assert_instance_of SponsorsListing::Receipt, @receipt
      assert_equal @listing, @receipt.sponsors_listing
      assert_equal @sponsorable.login, @receipt.sponsorable_login
      assert_equal @tax_id, @receipt.tax_id
      assert_equal Billing::Money.new(5_00, "GBP"), @receipt.total_payout
      assert_equal Billing::Money.new(5_00, "GBP"), @receipt.total_sponsorship
      assert_equal @start_date, @receipt.start_date
      assert_equal Time.at(@stripe_payout.created).utc, @receipt.end_date
    end
  end

  context ".for_sponsorable_and_year" do
    test "returns a receipt set up for the given sponsorable and numeric calendar year" do
      sponsorable = create(:user)
      listing = create(:sponsors_listing, :approved, :with_stripe_account,
        sponsorable: sponsorable)
      year = 2023
      tax_id = "8675309"

      result = SponsorsListing::Receipt.for_listing_and_year(
        sponsors_listing: listing,
        year: year,
        tax_id: tax_id,
      )

      start_date = DateTime.new(year, 1, 1)
      end_date = start_date.end_of_year

      assert_instance_of SponsorsListing::Receipt, result
      assert_equal listing, result.sponsors_listing
      assert_equal start_date, result.start_date
      assert_equal end_date, result.end_date
      assert_equal sponsorable.login, result.sponsorable_login
      assert_equal tax_id, result.tax_id
    end

    test "returns a receipt set up for the given sponsorable and string calendar year" do
      sponsorable = create(:user)
      listing = create(:sponsors_listing, :approved, :with_stripe_account,
        sponsorable: sponsorable)
      year = 2023
      tax_id = "8675309"

      result = SponsorsListing::Receipt.for_listing_and_year(
        sponsors_listing: listing,
        year: year,
        tax_id: tax_id,
      )

      start_date = DateTime.new(2023, 1, 1)
      end_date = start_date.end_of_year

      assert_instance_of SponsorsListing::Receipt, result
      assert_equal listing, result.sponsors_listing
      assert_equal start_date, result.start_date
      assert_equal end_date, result.end_date
      assert_equal sponsorable.login, result.sponsorable_login
      assert_equal tax_id, result.tax_id
    end

    test "total amount represents payouts for the given year" do
      sponsorable = create(:user)
      listing = create(:sponsors_listing, :approved, :with_stripe_account,
        sponsorable: sponsorable)
      year = 2021

      VCR.use_cassette("stripe/list_payouts_by_year") do
        result = SponsorsListing::Receipt.for_listing_and_year(
          sponsors_listing: listing,
          year: year,
        )

        assert_equal Billing::Money.new(26330, "USD"), result.total_payout
      end
    end

    test "total amount is zero when sponsorable has no payouts in given year" do
      sponsorable = create(:user)
      listing = create(:sponsors_listing, :approved, :with_stripe_account,
        sponsorable: sponsorable)
      year = 2008

      VCR.use_cassette("stripe/list_payouts_by_year") do
        result = SponsorsListing::Receipt.for_listing_and_year(
          sponsors_listing: listing,
          year: year,
        )

        assert_equal Billing::Money.new(0, "USD"), result.total_payout
      end
    end
  end

  context "#total_sponsorship" do
    test "returns the correct total sponsorship amount" do
      assert_equal Billing::Money.new(500, "GBP"), @receipt.total_sponsorship
    end
  end

  context "#pdf_filename" do
    test "contains expected file name" do
      assert_equal "sponsors-#{@listing.sponsorable}-statement-#{Date.current}.pdf", @receipt.pdf_filename
    end
  end

  context ".new" do
    test "raises argument error when sponsorable does not have a Stripe account" do
      sponsorable = create(:user, :sponsorable)

      assert_raises_with_message(ArgumentError, "Sponsorable must have a Stripe account") do
        SponsorsListing::Receipt.new(
          sponsors_listing: sponsorable.sponsors_listing,
          stripe_payout: @stripe_payout,
          start_date: DateTime.parse("2021-04-29"),
          end_date: DateTime.parse("2021-05-05"),
        )
      end
    end

    test "raises argument error when start_date is greater than end_date" do
      assert_raises_with_message(ArgumentError, "Start date must be before the end date") do
        SponsorsListing::Receipt.new(
          sponsors_listing: @listing,
          stripe_payout: @stripe_payout,
          start_date: DateTime.parse("2021-05-06"),
          end_date: DateTime.parse("2021-05-05"),
        )
      end
    end
  end
end
