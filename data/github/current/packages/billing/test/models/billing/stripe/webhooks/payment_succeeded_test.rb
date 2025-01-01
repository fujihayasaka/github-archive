# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::PaymentSucceededTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include GitHub::ZuoraTestHelper

  context ".service_fee_line_item?" do
    test "returns true for Stripe invoice line item with expected service_fee metadata" do
      line_item = Stripe::InvoiceLineItem.construct_from(
        "id" => "ii_1Mlcj1EQsq43iHhXlfMFEA12",
        "object" => "line_item",
        "amount" => 15,
        "metadata" => { "service_fee" => "true" },
      )
      assert Billing::Stripe::Webhooks::PaymentSucceeded.service_fee_line_item?(line_item)
    end

    test "returns true for Stripe invoice line item with expected description" do
      line_item = Stripe::InvoiceLineItem.construct_from(
        "id" => "ii_1MlEvEEQsq43iHhXFOguumoP",
        "object" => "line_item",
        "amount" => 15,
        "description" => "Service Fee. (3%)",
        "metadata" => {},
      )
      assert Billing::Stripe::Webhooks::PaymentSucceeded.service_fee_line_item?(line_item)
    end

    test "returns false for Stripe invoice line item with neither expected description nor metadata" do
      line_item = Stripe::InvoiceLineItem.construct_from(
        "id" => "ii_1MlEutEQsq43iHhXteKktdRi",
        "object" => "line_item",
        "amount" => 485,
        "description" => "GitHub Sponsors Program",
        "metadata" => {},
      )
      refute Billing::Stripe::Webhooks::PaymentSucceeded.service_fee_line_item?(line_item)
    end
  end

  test "raises exception when Sponsors-purpose Zuora account fails to create" do
    receiving_org = create(:organization)

    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: "#{receiving_org.login}" },
        amount_due: 25_00,
        amount_paid: 25_00,
        paid: true,
      },
    )

    Billing::CreateCustomer.expects(:perform).once.with(
      receiving_org,
      actor: User.staff_user,
      details: { omit_billing_info: true },
      purpose: :sponsors,
    ).returns(GitHub::Billing::Result.failure("It's all gone wrong"))

    error = assert_raises(Billing::Stripe::Webhooks::PaymentSucceeded::ZuoraAccountCreationError) do
      Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)
    end

    assert_equal "Failed to create Zuora account for #{receiving_org}: It's all gone wrong", error.message
  end

  test "creates a Sponsors-purpose Zuora account if none exists and applies a credit balance" do
    receiving_org = create(:organization)
    amount = Billing::Money.new(25_00)

    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: "#{receiving_org.login}" },
        amount_due: amount.cents,
        amount_paid: amount.cents,
        paid: true,
      },
    )

    assert_nil receiving_org.sponsors_customer
    assert_nil receiving_org.customer

    with_live_zuora("zuora/process_stripe_invoice_payment_webhook") do
      result = Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)
      refute_nil result
      result = T.must(result)
      assert result.success?

      sponsors_customer = receiving_org.reload_sponsors_customer
      assert_predicate sponsors_customer, :zuora?
      assert_nil receiving_org.reload_customer, "should not affect the general-purpose customer"

      account = sponsors_customer.zuora_account
      assert_equal amount.dollars, account["metrics"]["creditBalance"]

      payment = get_payment(result.zuora_result["Id"])
      assert_equal "automated payment from Stripe invoice", payment["Comment"]
      assert_equal webhook.payload["data"]["object"]["id"], payment["ReferenceId"]
    end
  end

  test "increases credit balance for the existing Sponsors-purpose Zuora account balance" do
    receiving_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    sponsors_customer = receiving_org.sponsors_customer
    sponsors_customer.update(zuora_account_id: "2c92c0fa6680fcc501669ce12cfe187d")

    amount = Billing::Money.new(25_00)

    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: "#{receiving_org.login}" },
        amount_due: amount.cents,
        amount_paid: amount.cents,
        paid: true,
      },
    )

    with_live_zuora("zuora/process_existing_customer_stripe_invoice_payment_webhook") do
      existing_balance = sponsors_customer.zuora_account["metrics"]["creditBalance"]

      result = Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)
      refute_nil result
      result = T.must(result)

      assert result.success?
      sponsors_account = sponsors_customer.zuora_account
      new_balance = sponsors_account["metrics"]["creditBalance"]
      assert_equal amount.dollars, new_balance - existing_balance

      payment = get_payment(result.zuora_result["Id"])
      assert_equal "automated payment from Stripe invoice", payment["Comment"]
      assert_equal webhook.payload["data"]["object"]["id"], payment["ReferenceId"]
    end
  end

  # https://github.com/github/sponsors/issues/4763
  test "does not include Sponsors fees in the credit balance adjustment" do
    receiving_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    invoice = VCR.use_cassette("stripe/retrieve_invoice") do
      # https://dashboard.stripe.com/test/invoices/in_1MnmiaEQsq43iHhXWBl49ZmE
      Stripe::Invoice.retrieve("in_1MnmiaEQsq43iHhXWBl49ZmE")
    end
    webhook = create(:stripe_webhook, :invoice_payment_succeeded, object: invoice.to_h.merge(
      metadata: { receiving_org: receiving_org.login },
      # act like the invoice has been fully paid:
      amount_due: invoice.amount_due,
      amount_paid: invoice.amount_due,
      amount_remaining: 0,
      paid: true,
    ))

    Billing::Sponsors::Invoiced::IncreaseCreditBalance.expects(:perform).once.with(
      actor: User.staff_user,
      sponsor: receiving_org,
      amount: Billing::Money.new(485), # $5 invoice with $0.15 in fees so org should get $4.85 to a credit balance
      comment: "automated payment from Stripe invoice",
      reference_id: invoice.id,
      via_automation: true,
    ).returns(GitHub::Billing::Result.success)

    Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)

    assert_dogstats_increment 1, Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX
    assert_dogstats_count_value 485, "#{Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX}." \
      "credit_balance_adjustment_amount_in_cents"
    assert_dogstats_count_value 500, "#{Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX}." \
      "invoice_amount_in_cents"
    assert_dogstats_count_value 15, "#{Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX}." \
      "invoice_fees_amount_in_cents"
  end

  test "processes hook and applies full invoice amount minus fees if paid invoice has amount remaining within our tolerances" do
    # https://github.com/github/sponsors/issues/6221
    receiving_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    invoice = VCR.use_cassette("stripe/retrieve_invoice") do
      # https://dashboard.stripe.com/test/invoices/in_1MnmiaEQsq43iHhXWBl49ZmE
      Stripe::Invoice.retrieve("in_1MnmiaEQsq43iHhXWBl49ZmE")
    end

    webhook = create(:stripe_webhook, :invoice_payment_succeeded, object: invoice.to_h.merge(
      metadata: { receiving_org: receiving_org.login },
      # act like the invoice has been partially paid, but is within our requirements
      # to still be considered paid
      amount_due: invoice.amount_due - 2_00,
      amount_paid: invoice.amount_due,
      amount_remaining: 2_00,
      paid: true,
    ))

    Billing::Sponsors::Invoiced::IncreaseCreditBalance.expects(:perform).once.with(
      actor: User.staff_user,
      sponsor: receiving_org,
      # $5 invoice with $0.15 in fees, with $2 not paid, so org should have $2.85 added to their credit balance
      amount: Billing::Money.new(285),
      comment: "automated payment from Stripe invoice",
      reference_id: invoice.id,
      via_automation: true,
    ).returns(GitHub::Billing::Result.success)

    Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)

    assert_dogstats_increment 1, Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX
    assert_dogstats_count_value 285, "#{Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX}." \
      "credit_balance_adjustment_amount_in_cents"
    assert_dogstats_count_value 500, "#{Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX}." \
      "invoice_amount_in_cents"
    assert_dogstats_count_value 15, "#{Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX}." \
      "invoice_fees_amount_in_cents"
  end

  test "sends credit balance increase notification" do
    receiving_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
    sponsors_customer = receiving_org.sponsors_customer
    sponsors_customer.update(zuora_account_id: "2c92c0fa6680fcc501669ce12cfe187d")

    amount = Billing::Money.new(25_00)

    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: "#{receiving_org.login}" },
        amount_due: amount.cents,
        amount_paid: amount.cents,
        paid: true,
      },
    )

    with_live_zuora("zuora/process_existing_customer_stripe_invoice_payment_webhook") do
      existing_balance = sponsors_customer.zuora_account["metrics"]["creditBalance"]

      assert_enqueued_with(job: SponsorsCreditBalanceIncreaseNotificationJob, args: [{ sponsor: receiving_org }]) do
        Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)
      end
    end
  end

  test "does not update the Zuora account balance when receiving_org is missing" do
    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: nil },
        amount_due: 25_00,
        amount_paid: 25_00,
        paid: true,
      },
    )

    result = Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)

    assert_nil(result)
  end

  test "emits metric to datadog stripe.payment_succeeded" do
    receiving_org = create(:invoiced_organization, :sponsors_invoiced, login: "github")
    existing_zuora_account_balance = receiving_org.sponsors_customer.zuora_account["metrics"]["balance"]

    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: "#{receiving_org.login}" },
        amount_due: 25_00,
        amount_paid: 25_00,
        paid: true,
      },
    )

    Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)

    assert_dogstats_increment 1, Billing::Stripe::Webhooks::PaymentSucceeded::DATADOG_PREFIX
  end

  test "instruments invoice payment" do
    receiving_org = create(:invoiced_organization, :sponsors_invoiced, login: "github")

    webhook = create(:stripe_webhook, :invoice_payment_succeeded,
      object: {
        metadata: { receiving_org: "#{receiving_org}", actor: "#{receiving_org.admin}" },
        amount_due: 25_00,
        amount_paid: 25_00,
        paid: true,
      },
    )
    stripe_invoice = Stripe::Invoice.construct_from(webhook.payload.dig("data", "object"))
    invoice = Billing::Stripe::Invoice.from_invoice(stripe_invoice)

    Billing::Stripe::Webhooks::PaymentSucceeded.perform(webhook)

    expected_message = {
      action: "PAY",
      invoice: Hydro::EntitySerializer.sponsors_stripe_invoice(invoice),
    }

    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeInvoice")
    assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorsInvoicedAccountStripeInvoice")
  end

  def get_payment(zuora_payment_id)
    # TODO update zuorest client to support getting payments by ID
    client = GitHub.zuorest_client
    client.get("/v1/object/payment/#{zuora_payment_id}")
  end
end
