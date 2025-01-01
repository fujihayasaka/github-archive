# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::PaymentMethodTest < GitHub::TestCase
  include GitHub::BillingTest
  include GitHub::ZuoraTestHelper

  context "#fingerprint" do
    test "resolves from Braintree" do
      expected_fingerprint = "a nice unique value"
      zuora_payment_method = with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::Zuora::PaymentMethod.find("2c92c0f866536dab01665f17918e0892")
      end
      fake_braintree_payment_method = stub(unique_number_identifier: expected_fingerprint)
      Braintree::PaymentMethod.stubs(:find).returns(fake_braintree_payment_method)

      assert_equal expected_fingerprint, zuora_payment_method.fingerprint
    end

    test "resolves from Stripe v3 payment gateway Stripe account" do
      expected_fingerprint = "IbTyj6Zk8I5uBFNL"

      VCR.use_cassette("stripe/zuora_stripe_v3_payment_method") do
        # See https://stripe.com/docs/testing for test cards
        stripe_payment_method = Stripe::PaymentMethod.create(
          {
            type: "card",
            card: {
              number: "4242424242424242",
              exp_month: 8,
              exp_year: 2023,
              cvc: "314",
            },
          },
          {
            api_key: GitHub.stripe_v3_api_key
          }
        )
        fake_zuora_payment_method_id = "fakezuoraid"
        payment_method_id = stripe_payment_method.id

        GitHub.zuorest_client.expects(:query_action).once.returns(
          { "records" => [
              { "ResponseString" => "\"payment_method\": \"#{payment_method_id}\"" }
            ]
          }
        )
        GitHub.zuorest_client.expects(:get_payment_method).once.with(fake_zuora_payment_method_id).returns({ "Id" => fake_zuora_payment_method_id })

        zuora_payment_method = T.must(Billing::Zuora::PaymentMethod.find(fake_zuora_payment_method_id))

        assert_equal expected_fingerprint, zuora_payment_method.fingerprint

      end
    end

    test "resolves from Sponsors Stripe v2 payment gateway Stripe account" do
      expected_fingerprint = "ysjkyaGRASZFdCF0"

      VCR.use_cassette("stripe/zuora_sponsors_stripe_v2_payment_method") do
        # See https://stripe.com/docs/testing for test cards
        stripe_payment_method = Stripe::PaymentMethod.create(
          {
            type: "card",
            card: {
              number: "5555555555554444",
              exp_month: 8,
              exp_year: 2023,
              cvc: "314",
            },
          },
          {
            api_key: GitHub.stripe_api_key
          }
        )
        fake_zuora_payment_method_id = "fakezuoraid"
        payment_method_id = stripe_payment_method.id

        GitHub.zuorest_client.expects(:query_action).once.returns(
          { "records" => [
              { "ResponseString" => "\"payment_method\": \"#{payment_method_id}\"" }
            ]
          }
        )
        GitHub.zuorest_client.expects(:get_payment_method).once.with(fake_zuora_payment_method_id).returns({ "Id" => fake_zuora_payment_method_id })

        zuora_payment_method = T.must(Billing::Zuora::PaymentMethod.find(fake_zuora_payment_method_id))

        assert_equal expected_fingerprint, zuora_payment_method.fingerprint
      end
    end

    test "returns nil and reports when Stripe payment method id can't be resolved" do
      VCR.use_cassette("stripe/zuora_invalid_stripe_payment_method") do
        fake_zuora_payment_method_id = "fakezuoraid"
        payment_method_id = "invalid_id"

        GitHub.zuorest_client.expects(:query_action).once.returns(
          { "records" => [
              { "ResponseString" => "\"payment_method\": \"#{payment_method_id}\"" }
            ]
          }
        )
        GitHub.zuorest_client.expects(:get_payment_method).once.with(fake_zuora_payment_method_id).returns({ "Id" => fake_zuora_payment_method_id })

        zuora_payment_method = T.must(Billing::Zuora::PaymentMethod.find(fake_zuora_payment_method_id))

        Failbot.expects(:report!).once
        assert_nil zuora_payment_method.fingerprint
      end
    end
  end
end
