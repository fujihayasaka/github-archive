# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsStripeInvoicesLoaderTest < GitHub::TestCase
  if GitHub.sponsors_enabled?
    fixtures do
      @customer_id = "cus_GjorjPogEx19Rk"
    end

    context "#fetch" do
      test "fetches open invoices for a customer" do
        loader = Sponsors::StripeInvoicesLoader.new(
          customer_id: @customer_id,
          status: Sponsors::StripeInvoicesLoader::InvoiceStatus::Open,
          limit: 100,
        )

        result = VCR.use_cassette("stripe/list_open_invoices") { loader.fetch }
        assert_predicate result, :success?
        assert_nil result.error
        assert_equal 1, result.invoices.size

        invoice = result.invoices.first
        assert_equal "357D3950-0004", invoice["number"]
        assert_equal 6000_00, invoice["amount_due"]
        assert_equal 1688550940, invoice["created"]
      end

      test "fetches paid invoices for a customer" do
        loader = Sponsors::StripeInvoicesLoader.new(
          customer_id: @customer_id,
          status: Sponsors::StripeInvoicesLoader::InvoiceStatus::Paid,
          limit: 100,
        )

        result = VCR.use_cassette("stripe/list_paid_invoices") { loader.fetch }
        assert_predicate result, :success?
        assert_nil result.error
        assert_equal 3, result.invoices.size

        invoice = result.invoices.shift
        assert_equal "357D3950-0003", invoice["number"]
        assert_equal 5500_00, invoice["amount_due"]
        assert_equal 1687943605, invoice["created"]

        invoice = result.invoices.shift
        assert_equal "357D3950-0002", invoice["number"]
        assert_equal 5000_00, invoice["amount_due"]
        assert_equal 1687939559, invoice["created"]

        invoice = result.invoices.shift
        assert_equal "357D3950-0001", invoice["number"]
        assert_equal 100, invoice["amount_due"]
        assert_equal 1687929166, invoice["created"]
      end

      test "returns error from Stripe API" do
        loader = Sponsors::StripeInvoicesLoader.new(
          customer_id: "cus_hoshimachiSuisei",
          status: Sponsors::StripeInvoicesLoader::InvoiceStatus::Open,
          limit: 100,
        )

        result = VCR.use_cassette("stripe/list_invoices_invalid_customer_id") { loader.fetch }
        refute_predicate result, :success?
        assert_empty result.invoices
        assert_equal "No such customer: 'cus_hoshimachiSuisei'", result.error
      end
    end
  end
end
