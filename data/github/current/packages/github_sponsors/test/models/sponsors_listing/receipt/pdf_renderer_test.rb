# typed: true
# frozen_string_literal: true

require "test_helper"
require "pdf-reader"

class SponsorsListing::Receipt::PdfRendererTest < GitHub::TestCase
  include GitHub::Billing::CurrencyTestHelper

  fixtures do
    @sponsorable = create(:user, login: "testUser")
    @listing = create(:sponsors_listing, sponsorable: @sponsorable)
    @stripe_account = create(:stripe_connect_account, sponsors_listing: @listing)
  end

  setup do
    travel_to "2021-05-03"

    @address1 = "123 Main St"
    @address2 = "Roanoke, VA 24001"
    stripe_payout = Billing::Stripe::Payout.new(
      stripe_payout: Stripe::Payout.construct_from(
        id: "po_8675309",
        amount: 50_00,
        currency: "gbp",
        created: 1619971200,
      ),
      stripe_account_id: "acct_123abc",
    )
    @receipt = SponsorsListing::Receipt.for_payout(
      sponsors_listing: @listing,
      stripe_payout: stripe_payout,
      start_date: DateTime.parse("2021-04-29"),
      tax_id: "123-45-6789",
      sponsorable_address1: @address1,
      sponsorable_address2: @address2,
    )

    setup_currency_exchange
  end

  def pdf_text_for(receipt)
    renderer = SponsorsListing::Receipt::PdfRenderer.new(receipt)
    T.must(PDF::Reader.new(StringIO.new(renderer.render)).pages.first).text
  end

  test "includes GitHub name" do
    assert includes pdf_text_for(@receipt), "GitHub, Inc."
  end

  test "includes GitHub address" do
    text = pdf_text_for(@receipt)
    assert_includes text, "88 Colin P Kelly Jr St"
    assert_includes text, "San Francisco, CA 94107"
    assert_includes text, "United States"
  end

  test "includes tax ID of maintainer" do
    assert_match /Tax ID:\s+123-45-6789/, pdf_text_for(@receipt)
  end

  test "includes maintainer address" do
    text = pdf_text_for(@receipt)
    assert_includes text, @address1
    assert_includes text, @address2
  end

  test "includes login of maintainer" do
    text = pdf_text_for(@receipt)
    assert_includes text, "@testUser"
  end

  test "includes date receipt was generated" do
    travel_to("2021-05-03") do
      assert_match /Statement Date:\s+May 3, 2021/, pdf_text_for(@receipt)
    end
  end

  test "includes date range covered by receipt" do
    assert_match /Statement Period:\s+Apr 29, 2021 - May 2, 2021/, pdf_text_for(@receipt)
  end

  test "includes the correct currency code" do
    expected_regex = /Total Amount of Sponsorship through\n\s*GitHub Sponsors Program \(GBP\)\s*\£50.00/
    assert_match expected_regex, pdf_text_for(@receipt)
  end

  test "includes note on receipt generation" do
    expected_regex = /This is a report of the payments our records indicate you received from your sponsors\s*through the GitHub Sponsors Program during the above Statement Period./
    assert_match expected_regex, pdf_text_for(@receipt)
  end
end
