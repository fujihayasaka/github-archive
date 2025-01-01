# typed: true
# frozen_string_literal: true

require "test_helper"

class CollectZuoraInvoiceJobTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  test "uses the 'zuora' queue" do
    assert_enqueued_jobs(1, queue: "zuora") do
      CollectZuoraInvoiceJob.perform_later("foo", "bar")
    end
  end

  test "does not error on Zuora issues" do
    GitHub.zuorest_client.stubs(:create_invoice_collect)
      .with(anything)
      .raises(Zuorest::HttpError.new("bad zuora", {}))

    CollectZuoraInvoiceJob.perform_now("account", "invoice")
  end

  test "does not error on Faraday issues" do
    GitHub.zuorest_client.stubs(:create_invoice_collect)
      .with(anything)
      .raises(Faraday::TimeoutError.new("bad faraday"))

    CollectZuoraInvoiceJob.perform_now("account", "invoice")
  end

  test "collects the invoice on Zuora" do
    with_live_zuora("zuora/collecting_outstanding_invoice") do
      invoice = Billing::Zuora::Invoice.new("2c92c0fb658a4eb501658ca0a3bf5cde")
      assert invoice.balance.positive?

      CollectZuoraInvoiceJob.perform_now(
        "2c92c0fb658a4eb501658ca05e4d5c9e",
        "2c92c0fb658a4eb501658ca0a3bf5cde",
      )

      invoice = Billing::Zuora::Invoice.new("2c92c0fb658a4eb501658ca0a3bf5cde")
      assert invoice.balance.zero?
    end
  end
end if GitHub.billing_enabled?
