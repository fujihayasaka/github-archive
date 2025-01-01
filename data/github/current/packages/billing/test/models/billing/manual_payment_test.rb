# typed: true
# frozen_string_literal: true

require "test_helper"

class ManualPaymentTest < GitHub::TestCase

  fixtures do
    @user = create(:user, :zuora)
    @sponsors_plan_sub = create(:billing_plan_subscription, :zuora,
      customer: @user.customer,
      user: @user,
      purpose: :sponsors
    )
    @general_plan_sub = create(:billing_plan_subscription, :zuora,
      customer: @user.customer,
      user: @user,
      purpose: :general
    )
  end

  def mock_invoice(balance:, subscription_number:, invoice_number: "INV001")
    invoice = create(:zuora_invoice, amount: balance, invoiceNumber: invoice_number)
    invoice.stubs(:invoice_items).returns([
      Billing::Zuora::InvoiceItem.new({ "subscriptionName" => subscription_number })
    ])
    invoice
  end

  if GitHub.billing_enabled?
    context "#balance_due" do
      test "returns total balance when purpose omitted" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: @general_plan_sub.zuora_subscription_number),
          mock_invoice(balance: 4, subscription_number: @sponsors_plan_sub.zuora_subscription_number),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_equal 5, payment.balance_due.dollars
      end

      test "returns balance specific to purpose" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: @general_plan_sub.zuora_subscription_number),
          mock_invoice(balance: 4, subscription_number: @sponsors_plan_sub.zuora_subscription_number),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_equal 1, payment.balance_due(purpose: :general).dollars
        assert_equal 4, payment.balance_due(purpose: :sponsors).dollars
      end

      test "returns balance specific to purpose for a business" do
        business = create(:business, :with_self_serve_payment)
        sponsors_plan_sub = create(:billing_plan_subscription, :zuora,
          customer: business.customer,
          user: nil,
          purpose: :sponsors,
        )
        general_plan_sub = create(:billing_plan_subscription, :zuora,
          customer: business.customer,
          user: nil,
          purpose: :general,
        )
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_plan_sub.zuora_subscription_number),
          mock_invoice(balance: 4, subscription_number: sponsors_plan_sub.zuora_subscription_number),
        ])

        payment = Billing::ManualPayment.new(target: business)

        assert_equal 1, payment.balance_due(purpose: :general).dollars
        assert_equal 4, payment.balance_due(purpose: :sponsors).dollars
      end
    end

    context "#invoice_numbers" do
      test "returns invoice numbers specific to purpose" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
          mock_invoice(balance: 4, subscription_number: sponsors_sub, invoice_number: "INV003"),
          mock_invoice(balance: 8, subscription_number: sponsors_sub, invoice_number: "INV004"),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_same_elements %w[INV003 INV004], payment.invoice_numbers(purpose: :sponsors)
        assert_equal ["INV001"], payment.invoice_numbers(purpose: :general)
      end

      test "returns an empty array if the target doesn't have unpaid invoices for a purpose" do
        general_sub = @general_plan_sub.zuora_subscription_number

        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_equal [], payment.invoice_numbers(purpose: :sponsors)
        assert_equal ["INV001"], payment.invoice_numbers(purpose: :general)
      end
    end

    context "#requires_separate_payments?" do
      test "true if invoices due for sponsor and general plan subscriptions" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
          mock_invoice(balance: 2, subscription_number: sponsors_sub, invoice_number: "INV002"),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_predicate payment, :requires_separate_payments?
      end

      test "false if invoices only due for general or sponsors plan subscriptions" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number

        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
        ])

        general_payment = Billing::ManualPayment.new(target: @user)

        refute_predicate general_payment, :requires_separate_payments?

        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: sponsors_sub, invoice_number: "INV001"),
        ])

        sponsors_payment = Billing::ManualPayment.new(target: @user)

        refute_predicate sponsors_payment, :requires_separate_payments?
      end
    end

    context "#due_date" do
      test "returns manual dunning date if present" do
        manual_dunning_record = create(:manual_dunning_period, user: @user)

        payment = Billing::ManualPayment.new(target: @user)

        assert_equal manual_dunning_record.due_date.to_date, payment.due_date
      end

      test "return nil if not in manual dunning" do
        payment = Billing::ManualPayment.new(target: @user)

        assert_nil payment.due_date
      end
    end

    context "#purpose" do
      test "returns supplied purpose" do
        general_sub = @general_plan_sub.zuora_subscription_number

        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
        ])

        payment = Billing::ManualPayment.new(target: @user, purpose: :sponsors)

        refute_predicate payment, :requires_separate_payments?
        assert_equal :sponsors, payment.purpose, "should use purpose supplied by caller"
      end

      test "returns sponsors or general purpose if single payment due" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number

        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
        ])

        general_payment = Billing::ManualPayment.new(target: @user)

        refute_predicate general_payment, :requires_separate_payments?
        assert_equal :general, general_payment.purpose

        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: sponsors_sub, invoice_number: "INV001"),
        ])

        sponsors_payment = Billing::ManualPayment.new(target: @user)

        refute_predicate sponsors_payment, :requires_separate_payments?
        assert_equal :sponsors, sponsors_payment.purpose
      end

      test "returns nil if multiple payments required" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
          mock_invoice(balance: 2, subscription_number: sponsors_sub, invoice_number: "INV002"),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_predicate payment, :requires_separate_payments?
        assert_nil payment.purpose
      end

      # https://github.com/github/sponsors/issues/5188
      test "returns general purpose even if original plan subscription does not exist anymore" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: "THISDOESNOTEXIST", invoice_number: "INV001"),
        ])
        GitHub.zuorest_client.expects(:get_subscription).with("THISDOESNOTEXIST").returns({
          "success" => true,
          "subscriptionNumber" => "THISDOESNOTEXIST",
          Billing::PlanSubscription::PAYMENT_GATEWAY_FIELD => nil,
        })

        payment = Billing::ManualPayment.new(target: @user)
        assert_equal :general, payment.purpose
      end

      test "returns nil if no payment due" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])

        payment = Billing::ManualPayment.new(target: @user)

        assert_predicate payment.balance_due, :zero?
        assert_nil payment.purpose
      end
    end

    context "#single_payment?" do
      test "true when purpose specified by caller and multiple payment required" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
          mock_invoice(balance: 2, subscription_number: sponsors_sub, invoice_number: "INV002"),
        ])

        payment = Billing::ManualPayment.new(target: @user, purpose: :sponsors)

        assert_predicate payment, :requires_separate_payments?
        assert_predicate payment, :single_payment?
      end

      test "false when no purpose specified and multiple payments required" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        general_sub = @general_plan_sub.zuora_subscription_number
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 1, subscription_number: general_sub, invoice_number: "INV001"),
          mock_invoice(balance: 2, subscription_number: sponsors_sub, invoice_number: "INV002"),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        assert_predicate payment, :requires_separate_payments?
        refute_predicate payment, :single_payment?
      end

      test "true when only single payment required" do
        sponsors_sub = @sponsors_plan_sub.zuora_subscription_number
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([
          mock_invoice(balance: 2, subscription_number: sponsors_sub, invoice_number: "INV002"),
        ])

        payment = Billing::ManualPayment.new(target: @user)

        refute_predicate payment, :requires_separate_payments?
        assert_predicate payment, :single_payment?
      end
    end
  else
    test "does not attempt to query Zuora when billing disabled" do
      Billing::Zuora::Invoice.expects(:open_invoices_for_account).never

      payment = Billing::ManualPayment.new(target: @user)

      assert_equal 0, payment.balance_due.dollars
    end
  end
end
