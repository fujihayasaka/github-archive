# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsInvoicedSponsorshipLineItemTest < GitHub::TestCase
  fixtures do
    @today = Date.current.freeze
    @org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    @recurring_tier = create(:sponsors_tier, :recurring)
  end

  context ".for_org" do
    test "includes data from BillingTransaction::LineItems and InvoicedSponsorshipTransfers" do
      travel_to "2023-11-14"
      line_item = create(:billing_transaction_line_item, :sponsors,
                         plan_subscription: @org.sponsors_plan_subscription)
      transfer = create(:invoiced_sponsorship_transfer, sponsor: @org)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_equal result.first.created_at, line_item.created_at
      assert_equal result.first.amount_in_cents, line_item.amount_in_cents
      assert_equal result.last.created_at, transfer.created_at
      assert_equal result.last.amount_in_cents, transfer.amount_in_cents
    end

    test "does not include line items from other sponsors" do
      line_item = create(:billing_transaction_line_item, :sponsors)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_empty result
    end

    test "does not include non-sponsorship line items" do
      line_item = create(:billing_transaction_line_item, :shared_storage,
                         plan_subscription: @org.sponsors_plan_subscription)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_empty result
    end

    test "does not include line items that were not paid by the sponsor" do
      line_item = create(:billing_transaction_line_item, :sponsors,
                         plan_subscription: create(:billing_plan_subscription), amount_in_cents: 0)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_empty result
    end

    test "does not include transfers from other sponsors" do
      transfer = create(:invoiced_sponsorship_transfer)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_empty result
    end

    test "only includes data from line items created within a time range when a time range is given" do
      included_line_item = create(:billing_transaction_line_item, :sponsors,
                                  plan_subscription: @org.sponsors_plan_subscription,
                                  created_at: @today - 10.days, amount_in_cents: 1000)
      excluded_line_item = create(:billing_transaction_line_item, :sponsors,
                                  plan_subscription: @org.sponsors_plan_subscription,
                                  created_at: @today - 1.year, amount_in_cents: 2000)
      range = @today - 1.month..@today

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, time_range: range)

      assert_equal 1, result.length
      assert_equal 1000, result.first.amount_in_cents
    end

    test "only includes data from transfers created within a time range when a time range is given" do
      included_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, created_at: @today - 1.month,
                                 amount_in_cents: 1000)
      excluded_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, created_at: @today - 1.year,
                                 amount_in_cents: 2000)
      range = @today - 1.month..@today

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, time_range: range)

      assert_equal 1, result.length
      assert_equal 1000, result.first.amount_in_cents
    end

    test "handles time range with no end" do
      excluded_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 2000,
        created_at: @today - 1.day)
      included_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 1000,
        created_at: @today)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, time_range: @today..)

      assert_equal [10_00], result.map(&:amount_in_cents)
    end

    test "handles time range with no beginning and an inclusive end" do
      included_transfer = travel_to(@today) do
        create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 1000)
      end
      excluded_transfer = travel_to(@today + 1.day) do
        create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 2000)
      end

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, time_range: ..@today)

      assert_equal [10_00], result.map(&:amount_in_cents)
    end

    test "handles time range with no beginning and an exclusive end" do
      included_transfer = travel_to(@today - 1.hour) do
        create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 1000)
      end
      excluded_transfer1 = travel_to(@today) do
        create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 2000)
      end
      excluded_transfer2 = travel_to(@today + 1.day) do
        create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 3000)
      end

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, time_range: ...@today)

      assert_equal [10_00], result.map(&:amount_in_cents)
    end

    test "includes data from line items from all time when no range is given" do
      line_item1 = create(:billing_transaction_line_item, :sponsors,
                                  plan_subscription: @org.sponsors_plan_subscription,
                                  created_at: @today - 1.month, amount_in_cents: 1000)
      line_item2 = create(:billing_transaction_line_item, :sponsors,
                                  plan_subscription: @org.sponsors_plan_subscription,
                                  created_at: @today - 32.days, amount_in_cents: 2000)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_equal 2, result.length
    end

    test "includes data from transfer from all time when no range is given" do
      transfer1 = create(:invoiced_sponsorship_transfer, sponsor: @org, created_at: @today - 1.month,
                                 amount_in_cents: 1000)
      transfer2 = create(:invoiced_sponsorship_transfer, sponsor: @org, created_at: @today - 1.year,
                                 amount_in_cents: 2000)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_equal 2, result.length
    end

    test "accounts for recurring payments outside a given time range but does not include them in result" do
      # Works for any day that is not the first of the month so the
      #   invoiced_sponsorship_transfer fixture is created in the preceding month
      travel_to Date.parse("2022-03-31") do
        listing = create(:sponsors_listing, :approved, :with_stripe_account)
        transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, sponsors_listing: listing)
        create(:invoiced_sponsorship_transfer, sponsor: @org, sponsors_listing: listing,
          created_at: transfer.created_at - 32.days)
        range = transfer.created_at - 1.month..transfer.created_at

        result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, time_range: range)

        assert_equal 1, result.length
        assert_predicate result.first, :recurring?
      end
    end

    test "returns an array of InvoicedSponsorshipLineItem objects" do
      transfer = create(:invoiced_sponsorship_transfer, sponsor: @org)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org)

      assert_instance_of Array, result
      assert_instance_of Sponsors::InvoicedSponsorshipLineItem, result.first
    end

    test "returns an empty set for organizations without a sponsors plan subscription" do
      org = create(:organization, sponsors_plan_subscription: nil)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(org)

      assert_empty result
    end

    test "filters to just transfers and line items paying the given sponsorables" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      sponsorable = listing.sponsorable
      included_line_item = create(:billing_transaction_line_item, :sponsors, subscribable: listing.default_tier,
        plan_subscription: @org.sponsors_plan_subscription, amount_in_cents: 10_00)
      excluded_line_item = create(:billing_transaction_line_item, :sponsors,
        plan_subscription: @org.sponsors_plan_subscription, amount_in_cents: 50_00)
      included_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 13_00,
        sponsors_listing: listing)
      excluded_transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 25_00)

      result = Sponsors::InvoicedSponsorshipLineItem.for_org(@org, sponsorable_ids: [sponsorable.id])

      assert_equal 2, result.size
      assert_equal included_line_item.amount_in_cents + included_transfer.amount_in_cents,
        result.sum(&:amount_in_cents)
    end
  end

  context ".first_for_org" do
    test "returns information from the first InvoicedSponsorshipTransfer if one exists" do
      transfer = create(:invoiced_sponsorship_transfer, sponsor: @org, amount_in_cents: 200)
      line_item = create(:billing_transaction_line_item, :sponsors,
                         plan_subscription: @org.sponsors_plan_subscription, amount_in_cents: 300)

      result = Sponsors::InvoicedSponsorshipLineItem.first_for_org(@org)

      assert_equal transfer.amount_in_cents, result.amount_in_cents
    end

    test "returns information from the first Billing::BillingTransaction::LineItem if no InvoicedSponsorshipTransfer exists" do
      line_item = create(:billing_transaction_line_item, :sponsors,
                         plan_subscription: @org.sponsors_plan_subscription, amount_in_cents: 300)

      result = Sponsors::InvoicedSponsorshipLineItem.first_for_org(@org)

      assert_equal line_item.amount_in_cents, result.amount_in_cents
    end

    test "returns nil if the organization has never made a payment" do
      result = Sponsors::InvoicedSponsorshipLineItem.first_for_org(@org)

      assert_nil result
    end
  end

  context "#amount_in_cents" do
    test "returns the amount_in_cents property of a line item" do
      line_item = create(:billing_transaction_line_item, amount_in_cents: 1000)

      item = Sponsors::InvoicedSponsorshipLineItem.new(billable: line_item)

      assert_equal 1000, item.amount_in_cents
    end

    test "returns the amount_in_cents property of a transfer" do
      transfer = create(:invoiced_sponsorship_transfer, amount_in_cents: 1000)

      item = Sponsors::InvoicedSponsorshipLineItem.new(billable: transfer)

      assert_equal 1000, item.amount_in_cents
    end
  end

  context "#created_at" do
    test "returns the created_at property of a line item" do
      line_item = create(:billing_transaction_line_item)

      item = Sponsors::InvoicedSponsorshipLineItem.new(billable: line_item)

      assert_equal line_item.created_at, item.created_at
    end

    test "returns the created_at property of a transfer" do
      transfer = create(:invoiced_sponsorship_transfer)

      item = Sponsors::InvoicedSponsorshipLineItem.new(billable: transfer)

      assert_equal transfer.created_at, item.created_at
    end
  end

  context "#recurring?" do
    test "returns the recurring attribute of the tier when the billable is a Billing::BillingTransfer::LineItem" do
      tier = create(:sponsors_tier, :recurring)
      line_item = create(:billing_transaction_line_item, :sponsors, subscribable: tier)

      item = Sponsors::InvoicedSponsorshipLineItem.new(
        billable: line_item
      )

      assert_predicate item, :recurring?
    end
  end

  test "returns true if the sponsor made similar payments within a month" do
    listing = create(:sponsors_listing, :approved, :with_stripe_account)
    transfer1 = create(:invoiced_sponsorship_transfer, sponsors_listing: listing, sponsor: @org)
    transfer2 = create(:invoiced_sponsorship_transfer, sponsors_listing: listing, sponsor: @org,
                      created_at: transfer1.created_at - 1.month)

    item = Sponsors::InvoicedSponsorshipLineItem.new(
      billable: transfer1,
      transfers: [transfer1, transfer2]
    )

    assert_predicate item, :recurring?
  end

  context "#one_time?" do
    test "returns the one_time attribute of the tier when the billable is a sponsors tier" do
      tier = create(:sponsors_tier, :one_time)
      line_item = create(:billing_transaction_line_item, :sponsors, subscribable: tier)

      item = Sponsors::InvoicedSponsorshipLineItem.new(
        billable: line_item
      )

      assert_predicate item, :one_time?
    end

    test "returns true if the sponsor made similar payments within a month" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      transfer1 = create(:invoiced_sponsorship_transfer, sponsors_listing: listing)
      transfer2 = create(:invoiced_sponsorship_transfer, sponsors_listing: listing, created_at: transfer1.created_at - 32.days)

      item = Sponsors::InvoicedSponsorshipLineItem.new(
        billable: transfer1,
        transfers: [transfer1, transfer2]
      )

      assert_predicate item, :one_time?
    end
  end
end
