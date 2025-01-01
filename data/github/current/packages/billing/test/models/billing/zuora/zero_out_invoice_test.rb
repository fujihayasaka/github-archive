# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::ZeroOutInvoiceTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper

  context "#run" do
    context "a negative invoice with one credit item" do
      test "will zero it out" do
        with_live_zuora("zuora/zero_out_invoice/negative") do
          # https://apisandbox.zuora.com/apps/NewInvoice.do?method=view&invoice_number=INV00015531&flag=1
          invoice_id = "2c92c08579f08a070179f16ed4817c3d"

          invoice = Billing::Zuora::Invoice.new invoice_id
          assert_equal -7, invoice.balance

          Billing::Zuora::ZeroOutInvoice.run(invoice: invoice)

          zeroed_out_invoice = Billing::Zuora::Invoice.new invoice_id
          assert_equal 0, zeroed_out_invoice.balance
          assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:true"]
        end
      end

      test "increments zero out failure count on unsuccessful result" do
        with_live_zuora("zuora/zero_out_invoice/failure") do
          # https://apisandbox.zuora.com/apps/NewInvoice.do?method=view&invoice_number=INV00015531&flag=1
          invoice_id = "2c92c08579f08a070179f16ed4817c3d"
          GitHub.zuorest_client
            .expects(:create_action)
            .returns([{ success: false }])

          invoice = Billing::Zuora::Invoice.new invoice_id
          Billing::Zuora::ZeroOutInvoice.run(invoice: invoice)

          assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:false"]
        end
      end
    end

    context "a negative invoice with multiple items" do
      test "will increment zero out success count if all of the results are successful" do
        invoice_items = [
          build(:zuora_invoice_item, id: "1", chargeAmount: -800),
          build(:zuora_invoice_item, id: "2", chargeAmount: 100),
          build(:zuora_invoice_item, :zero_charge, id: "3"),
        ]
        invoice = build(:zuora_invoice, balance: -100, amount: -100)
        invoice.stubs(:invoice_items).returns(invoice_items)
        invoice.stubs(:lock_key).returns("1")

        GitHub.zuorest_client
          .expects(:create_action)
          .returns([{ success: true }, { success: true }, { success: true }, { success: true }])

        Billing::Zuora::ZeroOutInvoice.run(invoice: invoice)

        assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:true"]
      end

      test "will increment zero out failure count if at least one of the results are unsuccessful" do
        invoice_items = [
          build(:zuora_invoice_item, id: "1", chargeAmount: -800),
          build(:zuora_invoice_item, id: "2", chargeAmount: 100),
          build(:zuora_invoice_item, :zero_charge, id: "3"),
          build(:zuora_invoice_item, id: "4", chargeAmount: -300),
        ]
        invoice = build(:zuora_invoice, balance: -100, amount: -100)
        invoice.stubs(:invoice_items).returns(invoice_items)
        invoice.stubs(:lock_key).returns("1")

        GitHub.zuorest_client
          .expects(:create_action)
          .returns([{ success: true }, { success: true }, { success: false }, { success: true }])

        Billing::Zuora::ZeroOutInvoice.run(invoice: invoice)

        assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:false"]
      end
    end
  end
end
