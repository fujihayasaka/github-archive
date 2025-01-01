# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::CreateStripeInvoiceTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    # see stripe/create_invoice_with_fee_item.yml VCR cassette:
    @org_login = "testorg-1bde9a84d7f0ce31"
    @org = create(:invoiced_organization, :sponsors_invoiced, name: @org_login)
    @agreement_signature = create(:sponsors_invoiced_agreement_signature, organization: @org)

    @stripe_customer_id = "cus_NWHTE7nqw3aEcZ" # https://dashboard.stripe.com/test/customers/cus_NWHTE7nqw3aEcZ
    @fee_percentage = 3
    @amount_in_dollars = "5000.00"
    @purchase_order_number = "8675309"
    @actor = create(:user, :staff, login: "someStaffUser")
  end

  context ".call" do
    if GitHub.sponsors_enabled?
      test "creates an invoice with a fee item and a non-fee item when specified fee percentage is non-zero" do
        amount_money = Billing::Money.parse(@amount_in_dollars)
        expected_fee_cents = amount_money.cents * @fee_percentage / 100

        result = VCR.use_cassette("stripe/create_invoice_with_fee_item") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: @stripe_customer_id,
            fee_percentage: @fee_percentage,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: @purchase_order_number,
            actor: @actor,
            should_finalize: false,
          )
        end

        refute_nil result
        assert_predicate result, :success?
        assert_instance_of Stripe::Invoice, result.invoice
        assert_equal amount_money, result.total_money

        invoice = VCR.use_cassette("stripe/retrieve_invoice_with_item_metadata") do
          Stripe::Invoice.retrieve(result.invoice.id)
        end
        assert_equal "GitHub", invoice.account_name
        assert_equal "US", invoice.account_country
        refute_predicate invoice, :auto_advance
        assert_equal "PO ##{@purchase_order_number}\nGitHub Sponsors", invoice.description
        assert_equal @stripe_customer_id, invoice.customer
        assert_equal "usd", invoice.currency
        assert_equal amount_money.cents, invoice.amount_due
        assert_equal 0, invoice.amount_paid
        expected_metadata = {
          receiving_org: @org_login,
          actor: @actor.login,
          purchase_order_number: @purchase_order_number,
        }
        assert_same_hash(expected_metadata, invoice.metadata.to_h)
        assert_equal %w[ach_credit_transfer cashapp], invoice.payment_settings.payment_method_types
        assert_equal "draft", invoice.status
        assert_equal 2, invoice.lines.total_count
        fee_item = invoice.lines.detect { |item| item.metadata["service_fee"] == "true" }
        refute_nil fee_item
        assert_equal expected_fee_cents, fee_item.amount
        non_fee_item = invoice.lines.detect { |item| item.id != fee_item.id }
        refute_nil non_fee_item
        assert_equal amount_money.cents - expected_fee_cents, non_fee_item.amount
      end

      test "creates an invoice with only a non-fee item when specified fee percentage is zero" do
        amount_money = Billing::Money.parse(@amount_in_dollars)

        result = VCR.use_cassette("stripe/create_invoice_without_fee_item") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: @stripe_customer_id,
            fee_percentage: 0,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: @purchase_order_number,
            actor: @actor,
            should_finalize: false,
          )
        end

        refute_nil result
        assert_predicate result, :success?
        assert_instance_of Stripe::Invoice, result.invoice
        assert_equal amount_money, result.total_money

        invoice = VCR.use_cassette("stripe/retrieve_invoice_without_fee") do
          Stripe::Invoice.retrieve(result.invoice.id)
        end
        assert_equal "GitHub", invoice.account_name
        assert_equal "US", invoice.account_country
        refute_predicate invoice, :auto_advance
        assert_equal "PO ##{@purchase_order_number}\nGitHub Sponsors", invoice.description
        assert_equal @stripe_customer_id, invoice.customer
        assert_equal "usd", invoice.currency
        assert_equal amount_money.cents, invoice.amount_due
        assert_equal 0, invoice.amount_paid
        expected_metadata = {
          receiving_org: @org_login,
          actor: @actor.login,
          purchase_order_number: @purchase_order_number,
        }
        assert_same_hash(expected_metadata, invoice.metadata.to_h)
        assert_equal %w[ach_credit_transfer cashapp], invoice.payment_settings.payment_method_types
        assert_equal "draft", invoice.status
        assert_equal 1, invoice.lines.total_count
        fee_item = invoice.lines.detect { |item| item.metadata["service_fee"] == "true" }
        assert_nil fee_item
        non_fee_item = invoice.lines.first
        refute_nil non_fee_item
        assert_equal amount_money.cents, non_fee_item.amount
      end

      test "creates and finalizes an invoice with a fee item and a non-fee item when specified fee percentage is non-zero" do
        amount_money = Billing::Money.parse(@amount_in_dollars)
        expected_fee_cents = amount_money.cents * @fee_percentage / 100

        result = VCR.use_cassette("stripe/create_and_finalize_invoice_with_fee_item") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: @stripe_customer_id,
            fee_percentage: @fee_percentage,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: @purchase_order_number,
            actor: @actor,
            should_finalize: true,
          )
        end

        refute_nil result
        assert_predicate result, :success?
        assert_instance_of Stripe::Invoice, result.invoice
        assert_equal amount_money, result.total_money

        invoice = VCR.use_cassette("stripe/retrieve_finalized_invoice_with_item_metadata") do
          Stripe::Invoice.retrieve(result.invoice.id)
        end
        assert_equal "GitHub Sponsors Program", invoice.account_name
        assert_equal "US", invoice.account_country
        refute_predicate invoice, :auto_advance
        assert_equal "PO ##{@purchase_order_number}\nGitHub Sponsors", invoice.description
        assert_equal @stripe_customer_id, invoice.customer
        assert_equal "usd", invoice.currency
        assert_equal amount_money.cents, invoice.amount_due
        assert_equal 0, invoice.amount_paid
        expected_metadata = {
          receiving_org: @org_login,
          actor: @actor.login,
          purchase_order_number: @purchase_order_number,
        }
        assert_same_hash(expected_metadata, invoice.metadata.to_h)
        assert_equal %w[ach_credit_transfer cashapp], invoice.payment_settings.payment_method_types
        assert_equal "open", invoice.status
        assert_equal 2, invoice.lines.total_count
        fee_item = invoice.lines.detect { |item| item.metadata["service_fee"] == "true" }
        refute_nil fee_item
        assert_equal expected_fee_cents, fee_item.amount
        non_fee_item = invoice.lines.detect { |item| item.id != fee_item.id }
        refute_nil non_fee_item
        assert_equal amount_money.cents - expected_fee_cents, non_fee_item.amount
      end

      test "creates and finalizes an invoice with only a non-fee item when specified fee percentage is zero" do
        amount_money = Billing::Money.parse(@amount_in_dollars)

        result = VCR.use_cassette("stripe/create_and_finalize_invoice_without_fee_item") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: @stripe_customer_id,
            fee_percentage: 0,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: @purchase_order_number,
            actor: @actor,
            should_finalize: true,
          )
        end

        refute_nil result
        assert_predicate result, :success?
        assert_instance_of Stripe::Invoice, result.invoice
        assert_equal amount_money, result.total_money

        invoice = VCR.use_cassette("stripe/retrieve_finalized_invoice_without_fee") do
          Stripe::Invoice.retrieve(result.invoice.id)
        end
        assert_equal "GitHub Sponsors Program", invoice.account_name
        assert_equal "US", invoice.account_country
        refute_predicate invoice, :auto_advance
        assert_equal "PO ##{@purchase_order_number}\nGitHub Sponsors", invoice.description
        assert_equal @stripe_customer_id, invoice.customer
        assert_equal "usd", invoice.currency
        assert_equal amount_money.cents, invoice.amount_due
        assert_equal 0, invoice.amount_paid
        expected_metadata = {
          receiving_org: @org_login,
          actor: @actor.login,
          purchase_order_number: @purchase_order_number,
        }
        assert_same_hash(expected_metadata, invoice.metadata.to_h)
        assert_equal %w[ach_credit_transfer cashapp], invoice.payment_settings.payment_method_types
        assert_equal "open", invoice.status
        assert_equal 1, invoice.lines.total_count
        fee_item = invoice.lines.detect { |item| item.metadata["service_fee"] == "true" }
        assert_nil fee_item
        non_fee_item = invoice.lines.first
        refute_nil non_fee_item
        assert_equal amount_money.cents, non_fee_item.amount
      end

      test "creates and finalizes an invoice without a purchase order number" do
        amount_money = Billing::Money.parse(@amount_in_dollars)
        expected_fee_cents = amount_money.cents * @fee_percentage / 100

        result = VCR.use_cassette("stripe/create_and_finalize_invoice_without_po_number") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: @stripe_customer_id,
            fee_percentage: @fee_percentage,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: nil,
            actor: @actor,
            should_finalize: true,
          )
        end

        refute_nil result
        assert_predicate result, :success?
        assert_instance_of Stripe::Invoice, result.invoice
        assert_equal amount_money, result.total_money

        invoice = VCR.use_cassette("stripe/retrieve_finalized_invoice_without_po_number") do
          Stripe::Invoice.retrieve(result.invoice.id)
        end
        assert_equal "GitHub Sponsors Program", invoice.account_name
        assert_equal "US", invoice.account_country
        refute_predicate invoice, :auto_advance
        assert_equal "GitHub Sponsors", invoice.description
        assert_equal @stripe_customer_id, invoice.customer
        assert_equal "usd", invoice.currency
        assert_equal amount_money.cents, invoice.amount_due
        assert_equal 0, invoice.amount_paid
        expected_metadata = {
          receiving_org: @org_login,
          actor: @actor.login,
        }
        assert_same_hash(expected_metadata, invoice.metadata.to_h)
        assert_equal %w[ach_credit_transfer cashapp], invoice.payment_settings.payment_method_types
        assert_equal "open", invoice.status
        assert_equal 2, invoice.lines.total_count
        fee_item = invoice.lines.detect { |item| item.metadata["service_fee"] == "true" }
        refute_nil fee_item
        assert_equal expected_fee_cents, fee_item.amount
        non_fee_item = invoice.lines.detect { |item| item.id != fee_item.id }
        refute_nil non_fee_item
        assert_equal amount_money.cents - expected_fee_cents, non_fee_item.amount
      end

      test "instruments Hydro event" do
        result = VCR.use_cassette("stripe/create_invoice_with_fee_item") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: @stripe_customer_id,
            fee_percentage: @fee_percentage,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: @purchase_order_number,
            actor: @actor,
            should_finalize: false,
          )
        end

        invoice = Billing::Stripe::Invoice.from_invoice(result.invoice)

        expected_message = {
          action: "CREATE",
          invoice: Hydro::EntitySerializer.sponsors_stripe_invoice(invoice),
        }

        assert_predicate result, :success?
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeInvoice")
        assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeInvoice")
      end

      test "requires org param to not be nil" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: nil,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Please specify which organization should receive the invoice.", result.error
      end

      test "requires actor param to not be nil" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: nil,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Please specify who is creating the invoice.", result.error
      end

      test "requires org param to be an organization" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: create(:user),
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Please specify which organization should receive the invoice.", result.error
      end

      test "requires actor param to be a user" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @org,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Please specify who is creating the invoice.", result.error
      end

      test "requires amount_in_dollars param to not be nil" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: nil,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Please specify the dollar amount of the invoice.", result.error
      end

      test "requires amount_in_dollars param to be at least the minimum required amount" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        minimum_amount = Billing::Money.new(Customer::SponsorsDependency::MINIMUM_INVOICE_AMOUNT_IN_CENTS)

        result = Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: (minimum_amount.dollars - 5).to_s,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        formatted_minimum = minimum_amount.format(no_cents_if_whole: true, with_currency: true)
        assert_equal "Please specify an amount that is at least #{formatted_minimum}.", result.error
      end

      test "requires a Stripe customer ID" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: "",
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Please specify which Stripe customer should receive the invoice.", result.error
      end

      test "requires stripe_customer_id param to be the ID of a Stripe customer" do
        Stripe::InvoiceItem.expects(:create).never

        result = VCR.use_cassette("stripe/create_and_finalize_invoice_with_invalid_customer") do
          Sponsors::CreateStripeInvoice.call(
            org: @org,
            stripe_customer_id: "foo",
            fee_percentage: @fee_percentage,
            amount_in_dollars: @amount_in_dollars,
            purchase_order_number: @purchase_order_number,
            actor: @actor,
            should_finalize: true,
          )
        end

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Failed to create invoice: No such customer: 'foo'", result.error
      end

      test "requires a sponsors invoiced org" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        org = create(:credit_card_org)
        result = Sponsors::CreateStripeInvoice.call(
          org: org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "Organization must be signed up for invoicing before creating an invoice.", result.error
      end

      test "includes purchase order number in description" do
        arg_matcher = ->(args) do
          refute_nil args[:description]
          assert_includes args[:description], "PO ##{@purchase_order_number}"
        end
        some_invoice = VCR.use_cassette("stripe/retrieve_finalized_invoice") do
          Stripe::Invoice.retrieve("in_1MnmiaEQsq43iHhXWBl49ZmE")
        end
        Stripe::Invoice.expects(:create).once.with(&arg_matcher).returns(some_invoice)

        Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )
      end

      test "includes receiving_org in invoice metadata" do
        arg_matcher = ->(args) do
          refute_nil args[:metadata]
          assert_equal @org_login, args[:metadata][:receiving_org]
        end
        some_invoice = VCR.use_cassette("stripe/retrieve_invoice") do
          Stripe::Invoice.retrieve("in_1MnmiaEQsq43iHhXWBl49ZmE")
        end
        Stripe::Invoice.expects(:create).once.with(&arg_matcher).returns(some_invoice)

        Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )
      end

      # https://github.com/github/sponsors/issues/4903
      test "includes appropriate payment methods in invoice options" do
        arg_matcher = ->(args) do
          assert_equal %w[ach_credit_transfer cashapp], args[:payment_settings][:payment_method_types]
        end
        some_invoice = VCR.use_cassette("stripe/retrieve_finalized_invoice") do
          Stripe::Invoice.retrieve("in_1MnmiaEQsq43iHhXWBl49ZmE")
        end
        Stripe::Invoice.expects(:create).once.with(&arg_matcher).returns(some_invoice)

        Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )
      end

      test "sets due date a month in the future" do
        freeze_time
        arg_matcher = ->(args) do
          assert_equal (GitHub::Billing.now + 1.month).to_i, args[:due_date]
        end
        some_invoice = VCR.use_cassette("stripe/retrieve_finalized_invoice") do
          Stripe::Invoice.retrieve("in_1MnmiaEQsq43iHhXWBl49ZmE")
        end
        Stripe::Invoice.expects(:create).once.with(&arg_matcher).returns(some_invoice)

        Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )
      end
    else
      test "requires Sponsors to be a feature" do
        Stripe::Invoice.expects(:create).never
        Stripe::InvoiceItem.expects(:create).never

        result = Sponsors::CreateStripeInvoice.call(
          org: @org,
          stripe_customer_id: @stripe_customer_id,
          fee_percentage: @fee_percentage,
          amount_in_dollars: @amount_in_dollars,
          purchase_order_number: @purchase_order_number,
          actor: @actor,
          should_finalize: true,
        )

        refute_nil result
        refute_predicate result, :success?
        assert_equal "GitHub Sponsors is not a feature.", result.error
      end
    end
  end
end
