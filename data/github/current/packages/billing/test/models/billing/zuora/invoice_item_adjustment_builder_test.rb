# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingZuoraInvoiceItemAdjustmentBuilderTest < GitHub::TestCase
  context "#perform" do
    test "returns an empty array when the invoice amount is zero" do
      invoice_items = []
      invoice = build(:zuora_invoice, amount: 0, balance: 0)
      invoice.stubs(:invoice_items).returns(invoice_items)

      Failbot.expects(:report).never

      adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
        invoice: invoice,
        adjustment_amount: Billing::Money.new(100)
      )

      assert_empty adjustments
    end

    test "returns an empty array when the adjustment amount is zero" do
      invoice_items = [build(:zuora_invoice_item, chargeAmount: 100)]
      invoice = build(:zuora_invoice, amount: 100, balance: 100)
      invoice.stubs(:invoice_items).returns(invoice_items)

      Failbot.expects(:report).never

      adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
        invoice: invoice,
        adjustment_amount: Billing::Money.new(0)
      )

      assert_empty adjustments
    end

    context "for an invoice with a positive amount" do
      test "returns an empty array and reports to FailBot when the adjustment amount is invalid" do
        invoice_items = [build(:zuora_invoice_item, id: "1", chargeAmount: 100)]
        invoice = build(:zuora_invoice, amount: 100, balance: 100)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).with(instance_of(ArgumentError), anything).twice

        # Positive adjustment that results in invoice balance = invoice amount + $0.01
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(1)
        )
        assert_empty adjustments

        # Negative adjustment that results in invoice balance = -$0.01
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-10001)
        )
        assert_empty adjustments
      end

      test "returns a single adjustment when zeroing out an invoice with a single charge" do
        invoice_items = [
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, id: "2", chargeAmount: 100),
          build(:zuora_invoice_item, :zero_charge)
        ]
        invoice = build(:zuora_invoice, amount: 100, balance: 100)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(1, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(10000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("2", adjustment[:SourceId])
        assert_equal("Credit", adjustment[:Type])
      end

      test "returns a single adjustment when zeroing out an invoice with one charge and one adjustable credit" do
        invoice_items = [
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, id: "2", chargeAmount: 100),
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, chargeAmount: -50)
        ]
        invoice = build(:zuora_invoice, amount: 100, balance: 50)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(1, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(5000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("2", adjustment[:SourceId])
        assert_equal("Credit", adjustment[:Type])
      end

      test "returns a single adjustment when zeroing out an invoice with one charge and one non-adjustable credit" do
        invoice_items = [
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, id: "2", chargeAmount: 100),
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, chargeAmount: -50)
        ]
        invoice = build(:zuora_invoice, amount: 50, balance: 50)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(1, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(5000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("2", adjustment[:SourceId])
        assert_equal("Credit", adjustment[:Type])
      end

      test "returns multiple adjustments when zeroing out an invoice with multiple charges and credits" do
        invoice_items = [
          build(:zuora_invoice_item, id: "1", chargeAmount: -10),
          build(:zuora_invoice_item, id: "2", chargeAmount: 50),
          build(:zuora_invoice_item, id: "3", chargeAmount: -10),
          build(:zuora_invoice_item, id: "4", chargeAmount: 20),
          build(:zuora_invoice_item, id: "5", chargeAmount: -10),
          build(:zuora_invoice_item, id: "6", chargeAmount: 30),
          build(:zuora_invoice_item, id: "7", chargeAmount: -5),
          build(:zuora_invoice_item, id: "8", chargeAmount: -20)
        ]
        invoice = build(:zuora_invoice, amount: 80, balance: 65)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(2, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(5000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("2", adjustment[:SourceId])
        assert_equal("Credit", adjustment[:Type])
        adjustment = T.must(adjustments.last)
        assert_equal(Billing::Money.new(1500), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("6", adjustment[:SourceId])
        assert_equal("Credit", adjustment[:Type])
      end
    end

    context "for an invoice with a negative amount" do
      test "returns an empty array and reports to FailBot when the adjustment amount is invalid" do
        invoice_items = [
          build(:zuora_invoice_item, id: "1", chargeAmount: -100)
        ]
        invoice = build(:zuora_invoice, amount: -100, balance: -100)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).with(instance_of(ArgumentError), anything).twice

        # Positive adjustment that results in invoice balance = $0.01
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(10001)
        )
        assert_equal [], adjustments

        # Negative adjustment that results in invoice balance = -$100.01
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-1)
        )
        assert_equal [], adjustments
      end

      test "returns a single adjustment when zeroing out an invoice with a single credit" do
        charge_amount = -100
        negative_item = build(:zuora_invoice_item, chargeAmount: charge_amount)
        invoice_items = [
          build(:zuora_invoice_item, :zero_charge),
          negative_item,
          build(:zuora_invoice_item, :zero_charge)
        ]
        invoice = build(:zuora_invoice, amount: charge_amount, balance: charge_amount)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(1, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(negative_item.charge_amount.abs, adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal(negative_item.id, adjustment[:SourceId])
        assert_equal("Charge", adjustment[:Type])
      end

      test "returns a single adjustment when zeroing out an invoice with one charge and one adjustable credit" do
        negative_charge_amount = -100
        negative_item = build(:zuora_invoice_item, chargeAmount: negative_charge_amount)
        charge_amount = 50
        invoice_items = [
          build(:zuora_invoice_item, :zero_charge),
          negative_item,
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, chargeAmount: 50)
        ]
        invoice = build(:zuora_invoice, amount: negative_charge_amount, balance: negative_charge_amount + charge_amount)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(1, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(5000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal(negative_item.id, adjustment[:SourceId])
        assert_equal("Charge", adjustment[:Type])
      end

      test "returns a single adjustment when zeroing out an invoice with one charge and one non-adjustable credit" do
        negative_charge_amount = -100
        negative_item = build(:zuora_invoice_item, chargeAmount: negative_charge_amount)
        charge_amount = 50
        invoice_items = [
          build(:zuora_invoice_item, :zero_charge),
          negative_item,
          build(:zuora_invoice_item, :zero_charge),
          build(:zuora_invoice_item, chargeAmount: 50)
        ]
        invoice = build(:zuora_invoice, amount: -charge_amount, balance: -charge_amount)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(1, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(5000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal(negative_item.id, adjustment[:SourceId])
        assert_equal("Charge", adjustment[:Type])
      end

      test "returns multiple adjustments when zeroing out an invoice with multiple charges and credits" do
        invoice_items = [
          build(:zuora_invoice_item, id: "1", chargeAmount: 10),
          build(:zuora_invoice_item, id: "2", chargeAmount: -50),
          build(:zuora_invoice_item, id: "3", chargeAmount: 10),
          build(:zuora_invoice_item, id: "4", chargeAmount: -20),
          build(:zuora_invoice_item, id: "5", chargeAmount: 10),
          build(:zuora_invoice_item, id: "6", chargeAmount: -30),
          build(:zuora_invoice_item, id: "7", chargeAmount: 5),
          build(:zuora_invoice_item, id: "8", chargeAmount: 20)
        ]
        invoice = build(:zuora_invoice, amount: -80, balance: -65)
        invoice.stubs(:invoice_items).returns(invoice_items)

        Failbot.expects(:report).never

        # Adjustment that zeros out the whole invoice balance
        adjustments = Billing::Zuora::InvoiceItemAdjustmentBuilder.perform(
          invoice: invoice,
          adjustment_amount: Billing::Money.new(-invoice.balance * 100)
        )

        assert_equal(2, adjustments.size)
        adjustment = T.must(adjustments.first)
        assert_equal(Billing::Money.new(5000), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("2", adjustment[:SourceId])
        assert_equal("Charge", adjustment[:Type])
        adjustment = T.must(adjustments.last)
        assert_equal(Billing::Money.new(1500), adjustment[:Amount])
        assert_equal(invoice.id, adjustment[:InvoiceId])
        assert_equal("6", adjustment[:SourceId])
        assert_equal("Charge", adjustment[:Type])
      end
    end
  end
end
