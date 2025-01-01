# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraZeroOutInvoicesTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper

  context ".for_account" do
    test "zeros out invoices on the account" do
      with_live_zuora("zuora/zero_out_account_invoices") do
        account_id      = "2c92c0fb6ccccd69016cd03273914f40"
        invoice_id      = "2c92c0fa6cccbae3016cd032a0273717"
        subscription_id = "2c92c0fa6cccbb56016cd03777484f81"

        invoice      = GitHub.zuorest_client.get_object_invoice invoice_id
        subscription = GitHub.zuorest_client.get_subscription subscription_id

        assert_equal 7, invoice["Balance"]
        assert_equal "Suspended", subscription["status"]

        response = Billing::Zuora::ZeroOutInvoices.for_account(account_id)
        assert response.success?

        invoice = GitHub.zuorest_client.get_object_invoice invoice_id
        assert_equal 0, invoice["Balance"]

        assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:true"]
      end
    end
  end

  context ".for_transaction" do
    test "zeroes out the full payment amount" do
      with_live_zuora("zuora/successful_zero_out") do
        zuora_transaction_id = "2c92c0fb62943e2c01629c87ddb30c2e"
        invoice_id = "2c92c0fb62943e2c01629c87dbed0c1c"

        invoice = ::Billing::Zuora::Invoice.new invoice_id
        assert_equal 7, invoice.balance

        response = Billing::Zuora::ZeroOutInvoices.for_transaction(zuora_transaction_id)

        assert response.success?
        invoice = ::Billing::Zuora::Invoice.new invoice_id
        assert_equal 0, invoice.balance
      end
    end

    test "zeroes out a partial refund from multiple items" do
      with_live_zuora("zuora/successful_partial_zero_out") do
        zuora_transaction_id = "2c92c0f9661ff98c0166301cc5981dba"
        invoice_id = "2c92c09a661fea790166301a941039c5"

        payment = Billing::Zuora::Payment.find(zuora_transaction_id)
        assert_equal 157, payment.amount
        invoice = Billing::Zuora::Invoice.new invoice_id
        assert_equal 50, invoice.balance

        response = Billing::Zuora::ZeroOutInvoices.for_transaction(zuora_transaction_id)

        assert response.success?
        invoice = Billing::Zuora::Invoice.new invoice_id
        assert_equal 0, invoice.balance

        assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:true"]
      end
    end

    test "returns success if an invoice isn't found" do
      zuora_transaction_id = "transaction-without-invoice"
      GitHub.zuorest_client.expects(:query_action).returns({ "records" => [] })

      response = Billing::Zuora::ZeroOutInvoices.for_transaction(zuora_transaction_id)

      assert response.success?
      assert_dogstats_increment 0, "zuora.invoices.zero_out"
    end

    test "raises error if any of the zero_out attempts failed" do
      with_live_zuora("zuora/transaction_failed_zero_out") do
        invoice1 = build(:zuora_invoice, amount: 5, balance: 5)
        invoice_item1 = build(:zuora_invoice_item, chargeAmount: 5)
        invoice1.stubs(:invoice_items).returns([invoice_item1])
        invoice2 = build(:zuora_invoice, amount: 5, balance: 5)
        invoice_item2 = build(:zuora_invoice_item, chargeAmount: 5)
        invoice2.stubs(:invoice_items).returns([invoice_item2])
        invoices = [invoice1, invoice2]

        Billing::Zuora::Invoice.expects(:invoices_for_transaction).returns(invoices)

        assert_raises Billing::Zuora::ZeroOutError do
          Billing::Zuora::ZeroOutInvoices.for_transaction("123abc")
        end
        assert_dogstats_increment 2, "zuora.invoices.zero_out", tags: ["success:false"]
      end
    end

    test "zeroes out multiple invoices if present" do
      with_live_zuora("zuora/zero_out_multiple_invoices") do
        zuora_transaction_id = "2c92c0f9661ff98c0166309e76650b65"
        invoices = Billing::Zuora::Invoice.invoices_for_transaction(zuora_transaction_id)

        assert_equal 2, invoices.count

        payment = Billing::Zuora::Payment.find(zuora_transaction_id)
        assert_equal 113, payment.amount

        response = Billing::Zuora::ZeroOutInvoices.for_transaction(zuora_transaction_id)

        assert response.success?

        invoices.each do |invoice|
          zuora_invoice = Billing::Zuora::Invoice.new invoice.invoice_id
          assert_equal 0, zuora_invoice.balance
        end

        assert_dogstats_increment 2, "zuora.invoices.zero_out", tags: ["success:true"]
      end
    end
  end

  context ".for_subscription" do
    test "returns success if an invoice isn't found" do
      zuora_transaction_id = "subscription-without-invoice"
      GitHub.zuorest_client.expects(:query_action).returns({ "records" => [] })

      response = Billing::Zuora::ZeroOutInvoices.for_subscription(
        zuora_transaction_id,
      )

      assert response.success?
      assert_dogstats_increment 0, "zuora.invoices.zero_out"
    end

    test "raises error if any of the zero_out attempts failed" do
      with_live_zuora("zuora/subscription_failed_zero_out") do
        invoice1 = build(:zuora_invoice, amount: 10, balance: 10)
        invoice_item1 = build(:zuora_invoice_item, chargeAmount: 5)
        invoice1.stubs(:invoice_items).returns([invoice_item1])
        invoice2 = build(:zuora_invoice, amount: 10, balance: 10)
        invoice_item2 = build(:zuora_invoice_item, chargeAmount: 5)
        invoice2.stubs(:invoice_items).returns([invoice_item2])
        invoices = [invoice1, invoice2]

        Billing::Zuora::Invoice.expects(:invoices_for_subscription).returns(invoices)

        error = assert_raises Billing::Zuora::ZeroOutError do
          Billing::Zuora::ZeroOutInvoices.for_subscription "123abc"
        end
        assert_match /Invalid value for field InvoiceId/, error.message
        assert_dogstats_increment 2, "zuora.invoices.zero_out", tags: ["success:false"]
      end
    end
  end

  context "#zero_out" do
    test "returns a successful response if the invoice is cancelled" do
      invoices = [
        stub(
          "invoice",
           cancelled?: true,
           invoice_id: "abc123",
          ),
        stub(
          "invoice",
           cancelled?: true,
           invoice_id: "abc123",
        ),
      ]

      invoice_zero_outter = ::Billing::Zuora::ZeroOutInvoices.new(
        invoices: invoices,
        invoice_belongs_to_type: "DOESNT MATTER",
        invoice_belongs_to_id: "STILL DOESNT",
      )

      # Ensure we aren't making live calls to zuora here
      GitHub.zuorest_client.expects(:query_action).never

      result = invoice_zero_outter.zero_out

      assert result.success
      assert_dogstats_increment 0, "zuora.invoices.zero_out"
    end

    test "returns a successful response if the invoice is showing a nil id" do
      invoices = [
        stub(
          "invoice",
           invoice_id: nil,
          ),
        stub(
          "invoice",
           invoice_id: nil,
        ),
      ]

      invoice_zero_outter = ::Billing::Zuora::ZeroOutInvoices.new(
        invoices: invoices,
        invoice_belongs_to_type: "DOESNT MATTER",
        invoice_belongs_to_id: "STILL DOESNT",
      )

      # Ensure we aren't making live calls to zuora here
      GitHub.zuorest_client.expects(:query_action).never

      result = invoice_zero_outter.zero_out

      assert result.success
      assert_dogstats_increment 0, "zuora.invoices.zero_out"
    end

    test "returns a successful response if unable to acquire a lock" do
      with_live_zuora("zuora/successful_zero_out") do
        zuora_transaction_id = "2c92c0fb62943e2c01629c87ddb30c2e"

        GitHub::Restraint.any_instance
          .expects(:lock!)
          .raises(GitHub::Restraint::UnableToLock)

        response = Billing::Zuora::ZeroOutInvoices.for_transaction(zuora_transaction_id)

        assert response.success?
        assert_dogstats_increment 0, "zuora.invoices.zero_out"
      end
    end

    test "raises error if one of the zero_out adjustments fail to get applied" do
      invoice_items = build_list(:zuora_invoice_item, 2, chargeAmount: 5)
      invoices = [build(:zuora_invoice, amount: 10, balance: 10)]
      invoices.first.stubs(:invoice_items).returns(invoice_items)

      GitHub.zuorest_client
        .expects(:create_action)
        .returns([{ success: true }, { success: false }])

      invoice_zero_outter = ::Billing::Zuora::ZeroOutInvoices.new(
        invoices: invoices,
        invoice_belongs_to_type: "DOESNT MATTER",
        invoice_belongs_to_id: "STILL DOESNT",
      )

      assert_raises Billing::Zuora::ZeroOutError do
        invoice_zero_outter.zero_out
      end
      assert_dogstats_increment 1, "zuora.invoices.zero_out", tags: ["success:false"]
    end
  end
end
