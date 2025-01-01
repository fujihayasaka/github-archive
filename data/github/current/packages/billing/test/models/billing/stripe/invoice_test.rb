# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::InvoiceTestCase < GitHub::BillingTestCase
  include HydroTestHelpers

  setup do
    invoice_fixture_path = Rails.root.join("test", "fixtures", "billing", "stripe", "events", "invoice_created.json")
    invoice_json = JSON.parse(File.read(invoice_fixture_path))
    @stripe_invoice = Stripe::Invoice.construct_from(invoice_json.dig("data", "object"))
    @invoice = Billing::Stripe::Invoice.from_invoice(@stripe_invoice)
  end

  test "#id returns Stripe invoice id" do
    assert_equal @stripe_invoice.id, @invoice.id
  end

  test "#number returns Stripe invoice number" do
    assert_equal @stripe_invoice.number, @invoice.number
  end

  test "#hosted_invoice_url returns Stripe hosted invoice url" do
    assert_equal @stripe_invoice.hosted_invoice_url, @invoice.hosted_invoice_url
  end

  test "#customer_id returns Stripe customer id" do
    assert_equal @stripe_invoice.customer, @invoice.customer_id
  end

  test "#status returns Stripe invoice status" do
    assert_equal @stripe_invoice.status, @invoice.status
  end

  test "#currency returns Stripe currency" do
    assert_equal @stripe_invoice.currency, @invoice.currency
  end

  test "#total returns Stripe total" do
    assert_equal @stripe_invoice.total, @invoice.total.cents
  end

  test "#paid? returns Stripe paid" do
    assert_equal @stripe_invoice.paid, @invoice.paid?
  end

  test "#amount_due returns Stripe amount due" do
    assert_equal @stripe_invoice.amount_due, @invoice.amount_due.cents
  end

  test "#amount_paid returns Stripe amount paid" do
    assert_equal @stripe_invoice.amount_paid, @invoice.amount_paid.cents
  end

  test "#amount_remaining returns Stripe amount remaining" do
    assert_equal @stripe_invoice.amount_remaining, @invoice.amount_remaining.cents
  end

  test "#service_fee returns Stripe invoice service fee" do
    fee_line_items = @stripe_invoice.lines.data.select { |li| li.metadata["service_fee"] == "true" }
    fee_amount_in_subunits = fee_line_items.sum(&:amount)
    assert_equal fee_amount_in_subunits, @invoice.service_fee.cents
  end

  test "#created_at returns Stripe created" do
    assert_equal Time.at(@stripe_invoice.created), @invoice.created_at
  end

  context "#receiving_org" do
    test "#receiving_org returns receiving org for Stripe invoice" do
      receiving_org = create(:organization, login: @stripe_invoice.metadata["receiving_org"])
      assert_equal receiving_org, @invoice.receiving_org
    end

    test "#receiving_org returns nil for unknown organization" do
      # will be nil since we didn't create the referenced org
      assert_nil @invoice.receiving_org
    end

    test "#receiving_org returns nil when metadata is nil" do
      @stripe_invoice.metadata = nil
      invoice = Billing::Stripe::Invoice.from_invoice(@stripe_invoice)
      assert_nil @invoice.receiving_org
    end
  end

  context "#purchase_order_number" do
    test "returns purchase order number if present in metadata" do
      po_number = "123ABC"
      @stripe_invoice.metadata["purchase_order_number"] = po_number
      invoice = Billing::Stripe::Invoice.from_invoice(@stripe_invoice)
      assert_equal po_number, invoice.purchase_order_number
    end

    test "returns nil if purchase order number not present in metadata" do
      assert_nil @stripe_invoice.metadata["purchase_order_number"]
      assert_nil @invoice.purchase_order_number
    end

    test "returns nil if metadata is nil" do
      @stripe_invoice.metadata = nil
      invoice = Billing::Stripe::Invoice.from_invoice(@stripe_invoice)
      assert_nil @invoice.purchase_order_number
    end
  end

  context "#creator" do
    test "returns Stripe invoice creator" do
      creator = create(:user, login: @stripe_invoice.metadata["actor"])
      assert_equal creator, @invoice.creator
    end

    test "returns ghost user when creator no longer exists" do
      assert_equal User.ghost, @invoice.creator
    end

    test "returns ghost user when metadata is nil" do
      @stripe_invoice.metadata = nil
      invoice = Billing::Stripe::Invoice.from_invoice(@stripe_invoice)
      assert_equal User.ghost, invoice.creator
    end
  end

  context "#instrument" do
    test "instruments Hydro event" do
      receiving_org = create(:organization, login: @stripe_invoice.metadata["receiving_org"])

      @invoice.instrument(action: "CREATE")

      expected_message = {
        action: "CREATE",
        invoice: Hydro::EntitySerializer.sponsors_stripe_invoice(@invoice),
      }

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeInvoice")
      assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeInvoice")
    end
  end
end
