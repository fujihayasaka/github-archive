# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::PaymentTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include GitHub::ZuoraTestHelper

  context ".find" do
    test "loads the payment from Zuora" do
      with_live_zuora("zuora/get_payment_by_id") do
        payment = Billing::Zuora::Payment.find("2c92c0fa6205232601622035ebfc5334")

        assert_instance_of Billing::Zuora::Payment, payment
        assert_equal "2c92c0fa6205232601622035ebfc5334", payment.id
      end
    end

    test "raises when a payment doesn't exist in Zuora" do
      with_live_zuora("zuora/get_payment_by_id") do
        assert_raises Zuorest::HttpError, "HTTP 404: Not Found" do
          Billing::Zuora::Payment.find("does_not_exist")
        end
      end
    end
  end

  test "#amount is the amount from Zuora" do
    zuorest_payment = Zuorest::Model::Payment.new("Amount" => 10.0)
    payment = Billing::Zuora::Payment.new(zuorest_payment)

    assert_equal 10.0, payment.amount
  end

  test "#amount_in_cents is the amount from Zuora, in cents" do
    zuorest_payment = Zuorest::Model::Payment.new("Amount" => 4.35)
    payment = Billing::Zuora::Payment.new(zuorest_payment)

    assert_equal 435, payment.amount_in_cents
  end

  test "#created_at is the date from Zuora" do
    zuorest_payment = Zuorest::Model::Payment.new("CreatedDate" => "2018-03-13T09:33:47.000-07:00")
    payment = Billing::Zuora::Payment.new(zuorest_payment)

    assert_equal Time.parse("2018-03-13T09:33:47.000-07:00"), payment.created_date
  end

  test "#is_retry? is true when the number of consecutive failures is > 0" do
    with_live_zuora("zuora/get_payment_by_id") do
      retry_payment = Billing::Zuora::Payment.find("2c92c0f9624bbc6c0162634bc47e31a9")
      assert_predicate retry_payment, :is_retry?

      first_time_payment = Billing::Zuora::Payment.find("2c92c0fa6205232601622035ebfc5334")
      refute_predicate first_time_payment, :is_retry?
    end
  end

  context "Braintree credit card charges" do
    test "#decorate_billing_transaction sets credit card-related fields" do
      billing_transaction = Billing::BillingTransaction.new

      zuorest_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Braintree",
        "ReferenceId" => "jgdxs6",
      )
      payment = Billing::Zuora::Payment.new(zuorest_payment)

      with_live_zuora("braintree/find_credit_card_transaction_by_id") do
        payment.decorate_billing_transaction(billing_transaction)
      end

      assert_equal "jgdxs6", billing_transaction.transaction_id
      assert billing_transaction.credit_card?
      assert_equal "411111", billing_transaction.bank_identification_number.to_s
      assert_equal "1111", billing_transaction.last_four
      assert_equal "Unknown", billing_transaction.country_of_issuance
      assert billing_transaction.settled?
    end

    test "#processor_response and #processor_response_code return the values from Braintree" do
      zuorest_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Braintree",
        "ReferenceId" => "jgdxs6",
      )
      payment = Billing::Zuora::Payment.new(zuorest_payment)

      with_live_zuora("braintree/find_credit_card_transaction_by_id") do
        assert_equal "1000", payment.processor_response_code
        assert_equal "Approved", payment.processor_response
      end
    end
  end

  context "PayPal Express Checkout charges" do
    test "#decorate_billing_transaction sets PayPal-related fields" do
      billing_transaction = Billing::BillingTransaction.new

      zuorest_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Paypal",
        "GatewayState" => "Settled",
        "PaymentMethodSnapshotId" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "ReferenceId" => "91K789326L4083315",
      )
      payment = Billing::Zuora::Payment.new(zuorest_payment)

      with_live_zuora("zuora/find_payment_method_snapshot_by_id") do
        payment.decorate_billing_transaction(billing_transaction)
      end

      assert_equal "91K789326L4083315", billing_transaction.transaction_id
      assert billing_transaction.paypal?
      assert_equal "zuora-buyer5@github.com", billing_transaction.paypal_email
      assert billing_transaction.settled?
    end

    test "#processor_response and #processor_response_code return the values from the Gateway" do
      zuorest_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Paypal",
        "GatewayState" => "Submitted",
        "PaymentMethodSnapshotId" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "ReferenceId" => "91K789326L4083315",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "Success",
      )
      payment = Billing::Zuora::Payment.new(zuorest_payment)

      with_live_zuora("zuora/find_payment_method_snapshot_by_id") do
        assert_equal "Success", payment.processor_response_code
        assert_equal "Approved", payment.processor_response
      end
    end

    test "#paypal? returns true" do
      zuorest_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Paypal",
        "GatewayState" => "Submitted",
        "PaymentMethodSnapshotId" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "ReferenceId" => "91K789326L4083315",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "Success",
      )
      payment = Billing::Zuora::Payment.new(zuorest_payment)

      assert_predicate payment, :paypal?
      refute_predicate payment, :stripe?
    end
  end

  context "Stripe credit card charges" do
    test "#decorate_billing_transaction sets credit card related fields" do
      billing_transaction = Billing::BillingTransaction.new

      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
        "BankIdentificationNumber" => "411111",
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        payment.decorate_billing_transaction(billing_transaction)
      end

      assert_equal charge_id, billing_transaction.transaction_id
      assert billing_transaction.credit_card?
      assert billing_transaction.settled?
      assert_equal "411111", billing_transaction.bank_identification_number.to_s
      assert_equal "1111", billing_transaction.last_four
      assert_equal "US", billing_transaction.country_of_issuance
    end

    test "#processor_response and #processor_response_code return the values from Stripe" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        assert_equal "200", payment.processor_response_code
        assert_equal "Approved", payment.processor_response
      end
    end

    test "#stripe? returns true" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      assert_predicate payment, :stripe?
      refute_predicate payment, :paypal?
    end
  end

  # The "Stripe v2" gateway in Zuora is identical to Stripe except that it
  # supports 3D Secure
  context "Stripe v2 credit card charges" do
    test "#decorate_billing_transaction sets credit card related fields" do
      billing_transaction = Billing::BillingTransaction.new

      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
        "BankIdentificationNumber" => "411111",
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        payment.decorate_billing_transaction(billing_transaction)
      end

      assert_equal charge_id, billing_transaction.transaction_id
      assert billing_transaction.credit_card?
      assert billing_transaction.settled?
      assert_equal "411111", billing_transaction.bank_identification_number.to_s
      assert_equal "1111", billing_transaction.last_four
      assert_equal "US", billing_transaction.country_of_issuance
    end

    test "#processor_response and #processor_response_code return the values from Stripe" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        assert_equal "200", payment.processor_response_code
        assert_equal "Approved", payment.processor_response
      end
    end

    test "#stripe? returns true for Stripe v2" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      assert_predicate payment, :stripe?
      refute_predicate payment, :paypal?
    end
  end

  # This payment gateway is used for sponsorships to ensure money doesn't co-mingle
  context "Sponsors Stripe v2 credit card charges" do
    test "#decorate_billing_transaction sets credit card related fields" do
      billing_transaction = Billing::BillingTransaction.new

      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Sponsors Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
        "BankIdentificationNumber" => "411111",
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        payment.decorate_billing_transaction(billing_transaction)
      end

      assert_equal charge_id, billing_transaction.transaction_id
      assert billing_transaction.credit_card?
      assert billing_transaction.settled?
      assert_equal "411111", billing_transaction.bank_identification_number.to_s
      assert_equal "1111", billing_transaction.last_four
      assert_equal "US", billing_transaction.country_of_issuance
    end

    test "#processor_response and #processor_response_code return the values from Stripe" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Sponsors Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        assert_equal "200", payment.processor_response_code
        assert_equal "Approved", payment.processor_response
      end
    end

    test "#stripe? returns true for Sponsors Stripe v2" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Sponsors Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      assert_predicate payment, :stripe?
      refute_predicate payment, :paypal?
    end
  end

  # This payment gateway is used for everything but sponsorships to ensure money doesn't co-mingle
  context "Stripe v3 credit card charges" do
    test "#decorate_billing_transaction sets credit card related fields" do
      billing_transaction = Billing::BillingTransaction.new

      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v3",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
        "BankIdentificationNumber" => "411111",
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        payment.decorate_billing_transaction(billing_transaction)
      end

      assert_equal charge_id, billing_transaction.transaction_id
      assert billing_transaction.credit_card?
      assert billing_transaction.settled?
      assert_equal "411111", billing_transaction.bank_identification_number.to_s
      assert_equal "1111", billing_transaction.last_four
      assert_equal "US", billing_transaction.country_of_issuance
    end

    test "#processor_response and #processor_response_code return the values from Stripe" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v3",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      with_live_zuora("zuora/stripe/find_credit_card_transaction_by_id") do
        assert_equal "200", payment.processor_response_code
        assert_equal "Approved", payment.processor_response
      end
    end

    test "#stripe? returns true for Stripe v3" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v3",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      assert_predicate payment, :stripe?
      refute_predicate payment, :paypal?
    end
  end

  context "#includes_sponsorship?" do
    test "true when positive Sponsors invoice item charge exists" do
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "some-gateway",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => "ch_1EfTT6EQsq43iHhXJTYv2P8m",
      )
      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: create(:sponsors_tier)),
      ]
      payment = Billing::Zuora::Payment.new(zuora_payment)
      payment.stubs(:invoice_items).returns(fake_invoice_items)

      assert_predicate payment, :includes_sponsorship?
    end

    test "false when only negative Sponsors invoice charge item exists" do
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "some-gateway",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => "ch_1EfTT6EQsq43iHhXJTYv2P8m",
      )
      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => -1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: create(:sponsors_tier)),
      ]
      payment = Billing::Zuora::Payment.new(zuora_payment)
      payment.stubs(:invoice_items).returns(fake_invoice_items)

      refute_predicate payment, :includes_sponsorship?
    end

    test "false when no Sponsors item exists" do
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "some-gateway",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => "ch_1EfTT6EQsq43iHhXJTYv2P8m",
      )
      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: create(:marketplace_listing_plan)),
        Billing::Zuora::InvoiceItem.new({
          "id" => "myotherfavoriteid",
          "unitPrice" => 1,
          "chargeName" => "other-charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }),
      ]
      payment = Billing::Zuora::Payment.new(zuora_payment)
      payment.stubs(:invoice_items).returns(fake_invoice_items)

      refute_predicate payment, :includes_sponsorship?
    end
  end

  context "#instrument" do
    test "emits metric if non-sponsorship payment uses Sponsors-specific payment gateway" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "sponsors-stripe-v2-payment-id",
        "AccountId" => "fake-account-id",
        "Amount" => 1.0,
        "Gateway" => "Sponsors Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      fake_invoice_items = [
        Billing::Zuora::InvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        })
      ]
      payment = Billing::Zuora::Payment.new(zuora_payment)
      payment.stubs(:invoice_items).returns(fake_invoice_items)
      expected_log = {
        "Body": "Improper Zuora payment gateway",
        "SeverityText": "ERROR",
        "code.namespace": "Billing::Zuora::Payment",
        "code.function": "instrument_improper_gateway",
        "gh.billing.zuora.account.id": "fake-account-id",
        "gh.billing.zuora.payment.improper_gateway.details": "general-payment-using-sponsors-gateway",
        "gh.billing.zuora.payment.id": "sponsors-stripe-v2-payment-id",
        "gh.billing.zuora.payment.gateway": "Sponsors Stripe v2",
      }

      assert_logged(**expected_log) do
        payment.instrument
      end

      expected_tags = [
        "details:general-payment-using-sponsors-gateway",
        "gateway:sponsors-stripe-v2",
      ]
      assert_dogstats_increment(1, "zuora.payment.improper_payment_gateway.count",
        tags: expected_tags,
      )
      assert_dogstats_count_value(100, "zuora.payment.improper_payment_gateway.amount_in_cents",
        tags: expected_tags,
      )
    end

    test "emits metric if non-sponsorship Stripe payment uses other payment gateway" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "stripe-v2-payment-id",
        "AccountId" => "fake-account-id",
        "Amount" => 1.0,
        "Gateway" => "Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      fake_invoice_items = [
        Billing::Zuora::InvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        })
      ]
      payment = Billing::Zuora::Payment.new(zuora_payment)
      payment.stubs(:invoice_items).returns(fake_invoice_items)
      expected_gateway_reason = "general-stripe-payment-using-non-general-purpose-stripe-gateway"
      expected_log = {
        "Body": "Improper Zuora payment gateway",
        "SeverityText": "ERROR",
        "code.namespace": "Billing::Zuora::Payment",
        "code.function": "instrument_improper_gateway",
        "gh.billing.zuora.account.id": "fake-account-id",
        "gh.billing.zuora.payment.improper_gateway.details": expected_gateway_reason,
        "gh.billing.zuora.payment.id": "stripe-v2-payment-id",
        "gh.billing.zuora.payment.gateway": "Stripe v2",
      }

      assert_logged(**expected_log) do
        payment.instrument
      end

      expected_tags = [
        "details:#{expected_gateway_reason}",
        "gateway:stripe-v2",
      ]
      assert_dogstats_increment(1, "zuora.payment.improper_payment_gateway.count",
        tags: expected_tags,
      )
      assert_dogstats_count_value(100, "zuora.payment.improper_payment_gateway.amount_in_cents",
        tags: expected_tags,
      )
    end

    test "emits metric if sponsorship payment uses non-Sponsors-specific payment gateway" do
      charge_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "stripe-v3-payment-id",
        "AccountId" => "fake-account-id",
        "Amount" => 1.0,
        "Gateway" => "Stripe v3",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => charge_id,
      )
      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: create(:sponsors_tier)),
      ]
      payment = Billing::Zuora::Payment.new(zuora_payment)
      payment.stubs(:invoice_items).returns(fake_invoice_items)
      expected_log = {
        "Body": "Improper Zuora payment gateway",
        "SeverityText": "ERROR",
        "code.namespace": "Billing::Zuora::Payment",
        "code.function": "instrument_improper_gateway",
        "gh.billing.zuora.account.id": "fake-account-id",
        "gh.billing.zuora.payment.improper_gateway.details": "sponsorship-payment-using-non-sponsors-gateway",
        "gh.billing.zuora.payment.id": "stripe-v3-payment-id",
        "gh.billing.zuora.payment.gateway": "Stripe v3",
      }

      assert_logged(**expected_log) do
        payment.instrument
      end

      expected_tags = [
        "details:sponsorship-payment-using-non-sponsors-gateway",
        "gateway:stripe-v3",
      ]
      assert_dogstats_increment(1, "zuora.payment.improper_payment_gateway.count",
        tags: expected_tags,
      )
      assert_dogstats_count_value(100, "zuora.payment.improper_payment_gateway.amount_in_cents",
        tags: expected_tags,
      )
    end

    test "does not emit metric if correct gateway used" do
      sponsors_zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Sponsors Stripe v2",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => "ch_1EfTT6EQsq43iHhXJTYv2P8m",
      )
      fake_sponsors_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: create(:sponsors_tier)),
      ]
      sponsors_payment = Billing::Zuora::Payment.new(sponsors_zuora_payment)
      sponsors_payment.stubs(:invoice_items).returns(fake_sponsors_invoice_items)

      non_sponsors_zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => "Stripe v3",
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => "ch_1EfTT6EQsq43iHhXJTYv2P8m",
      )
      fake_non_sponsors_invoice_items = [
        Billing::Zuora::InvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => 1,
          "chargeName" => "charge-name",
          "chargeAmount" => 1,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        })
      ]
      non_sponsors_payment = Billing::Zuora::Payment.new(non_sponsors_zuora_payment)
      non_sponsors_payment.stubs(:invoice_items).returns(fake_non_sponsors_invoice_items)

      sponsors_payment.instrument
      non_sponsors_payment.instrument

      refute_dogstats_increment "zuora.payment.improper_payment_gateway"
    end
  end
end
