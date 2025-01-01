# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingZuoraPaypalTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  context ".create_payment_method" do
    test "reports on braintree failure" do
      user = create(:user)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/paypal/braintree_failed_create_payment_method") do
        user.reload

        invalid_paypal_nonce = "garbage_string"

        response = Billing::ZuoraPaypal.create_payment_method(
          account_id: user.customer.zuora_account_id,
          paypal_nonce: invalid_paypal_nonce,
        )

        assert Failbot.reports.find { |report| Failbot.exception_classname_from_hash(report) == "Braintree::ValidationsFailed" }
        refute response[:success]
      end
    end

    test "creates a paypal payment method as the payment method for a zuora account" do
      user = create(:user)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/paypal/successful_create_payment_method") do
        user.reload

        response = Billing::ZuoraPaypal.create_payment_method(
          account_id: user.customer.zuora_account_id,
          paypal_nonce: "8c1e3132-ff2c-08c7-0de1-2fdce3c9880a",
        )

        assert response[:success]
        assert response[:payment_method_id].present?

        zuora_payment_method_response = GitHub.zuorest_client.get_payment_method(response[:payment_method_id])
        assert_equal user.customer.zuora_account_id, zuora_payment_method_response["AccountId"]
      end
    end
  end

  context ".create_account" do
    test "unsuccessful when the zuora customer object is not active" do
      with_live_zuora("zuora/successful_paypal_customer_create") do
        zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
        billing_address = {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        }

        target_details = {
          billed_on: zuora_user.billed_on.day,
          external_name: zuora_user.login,
          external_email: zuora_user.email,
          bt_fields: { user_id: zuora_user.id },
        }

        zuora_account_mock = mock("ZuoraAccount", id: "zuora-id", active?: false)
        ::Billing::Zuora::Account.stubs(:find).returns(zuora_account_mock)

        response = Billing::ZuoraPaypal.create_account(
          target_details: target_details,
          paypal_nonce: "4a70cbae-dbe2-0edf-02e8-63f52219ec2b",
          billing_address: billing_address,
          vat_code: nil,
        )

        refute response[:success]
      end
    end

    test "returns account information and success with a valid billing agreement" do
      zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
      billing_address = {
        country_code_alpha3: "USA",
        region: "New York",
        postal_code: "10036",
      }

      target_details = {
        billed_on: zuora_user.billed_on.day,
        external_name: zuora_user.login,
        external_email: zuora_user.email,
        bt_fields: { user_id: zuora_user.id },
      }

      with_live_zuora("zuora/successful_paypal_customer_create_not_tax_exempt") do
        response = Billing::ZuoraPaypal.create_account(
          target_details: target_details,
          paypal_nonce: "4a70cbae-dbe2-0edf-02e8-63f52219ec2b",
          billing_address: billing_address,
          vat_code: nil,
        )

        assert response[:success]
        assert response[:account_number]
        assert response[:account_id]
        assert response[:payment_method_id]

        zuora_account = Zuorest::Model::Account.find(response[:account_id])
        zuora_customer_info = zuora_account.body["basicInfo"]
        assert_equal "No", zuora_customer_info["SynctoNetSuite__NS"]
        assert_equal "Self-Serve", zuora_customer_info["BusinessSegment__c"]
        assert_equal "Batch10", zuora_customer_info["batch"]
        tax_info = zuora_account.body["taxInfo"]
        assert_equal "No", tax_info["exemptStatus"]
        assert_equal "N/A", tax_info["exemptCertificateId"]
      end
    end

    context "tax exemption status" do
      test "creates an account with tax exempt status set to No when no tax exemption status is provided" do
        zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
        billing_address = {
          country_code_alpha3: "USA",
          region: "",
          postal_code: "",
        }

        target_details = {
          billed_on: zuora_user.billed_on.day,
          external_name: zuora_user.login,
          external_email: zuora_user.email,
          bt_fields: { user_id: zuora_user.id },
        }

        GitHub.zuorest_client.expects(:create_object_account).with do |params|
          params[:TaxExemptStatus] == "No"
        end.returns({
          "Success" => true,
          "Id" => "2c92c0f862ceb69b0162d456d0cb37e5"
        })

        with_live_zuora("zuora/successful_paypal_customer_create") do
          Billing::ZuoraPaypal.create_account(
            target_details: target_details,
            paypal_nonce: "4a70cbae-dbe2-0edf-02e8-63f52219ec2b",
            billing_address: billing_address,
            vat_code: nil,
          )
        end
      end

      test "creates an account with tax exempt status set to No when a rejected tax exemption status is provided" do
        zuora_org = create(:no_credit_card_org, billed_on: Date.parse("2018-10-17"))
        billing_address = {
          country_code_alpha3: "USA",
          region: "",
          postal_code: "",
        }

        target_details = {
          billed_on: zuora_org.billed_on.day,
          external_name: zuora_org.login,
          external_email: zuora_org.email,
          bt_fields: { user_id: zuora_org.id },
        }

        tax_exemption_status = create(:tax_exemption_status, customer: zuora_org.customer, status: :rejected, status_reason: "Some reason")

        GitHub.zuorest_client.expects(:create_object_account).with do |params|
          params[:TaxExemptStatus] == "No"
        end.returns({
          "Success" => true,
          "Id" => "2c92c0f862ceb69b0162d456d0cb37e5"
        })

        with_live_zuora("zuora/successful_paypal_customer_create") do
          Billing::ZuoraPaypal.create_account(
            target_details: target_details,
            paypal_nonce: "4a70cbae-dbe2-0edf-02e8-63f52219ec2b",
            billing_address: billing_address,
            vat_code: nil,
            tax_exemption_status: tax_exemption_status,
          )
        end
      end

      test "creates an account with tax exempt status set to Yes when an approved tax exemption status is provided" do
        zuora_org = create(:no_credit_card_org, billed_on: Date.parse("2018-10-17"))
        billing_address = {
          country_code_alpha3: "USA",
          region: "",
          postal_code: "",
        }

        target_details = {
          billed_on: zuora_org.billed_on.day,
          external_name: zuora_org.login,
          external_email: zuora_org.email,
          bt_fields: { user_id: zuora_org.id },
        }

        tax_exemption_status = create(:tax_exemption_status, customer: zuora_org.customer, status: :approved)

        GitHub.zuorest_client.expects(:create_object_account).with do |params|
          params[:TaxExemptStatus] == "Yes"
        end.returns({
          "Success" => true,
          "Id" => "2c92c0f862ceb69b0162d456d0cb37e5"
        })

        with_live_zuora("zuora/successful_paypal_customer_create") do
          Billing::ZuoraPaypal.create_account(
            target_details: target_details,
            paypal_nonce: "4a70cbae-dbe2-0edf-02e8-63f52219ec2b",
            billing_address: billing_address,
            vat_code: nil,
            tax_exemption_status: tax_exemption_status,
          )
        end
      end
    end

    test "creates an account with Zuora APM enabled" do
      zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
      billing_address = {
        country_code_alpha3: "USA",
        region: "New York",
        postal_code: "10036",
      }

      target_details = {
        billed_on: zuora_user.billed_on.day,
        external_name: zuora_user.login,
        external_email: zuora_user.email,
        bt_fields: { user_id: zuora_user.id },
      }

      GitHub.zuorest_client.expects(:create_object_account)
        .with(has_entry(:APM__c, "True"))
        .returns({ "Id" => "fakezuoraid" })

      VCR.use_cassette("braintree/successful_create_paypal_customer") do
        Billing::ZuoraPaypal.create_account(
          target_details: target_details,
          paypal_nonce: Braintree::Test::Nonce::PayPalFuturePayment,
          billing_address: billing_address,
          vat_code: nil,
        )
      end
    end

    test "returns false success on invalid paypal_nonce" do
      with_live_zuora("zuora/failure_paypal_customer_create") do
        zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
        paypal_nonce = "bad-paypal-nonce"
        billing_address = {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        }

        target_details = {
          billed_on: zuora_user.billed_on.day,
          external_name: zuora_user.login,
          external_email: zuora_user.email,
          bt_fields: { user_id: zuora_user.id },
        }

        response = Billing::ZuoraPaypal.create_account(
          target_details: target_details,
          paypal_nonce: paypal_nonce,
          billing_address: billing_address,
          vat_code: nil,
        )

        refute response[:success]
      end
    end

    test "works for customers in the District of Columbia" do
      with_live_zuora("zuora/successful_paypal_customer_create") do
        zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
        billing_address = {
          country_code_alpha3: "USA",
          region: "District of Columbia",
          postal_code: "20005",
        }

        Failbot.stubs(:report!)
        Failbot.expects(:report!).with do |_, kwargs|
          errors = kwargs.dig(:zuora_response, "Errors") || []
          errors.any? do |error|
            /is not an ISO state\/province/.match?(error["Message"])
          end
        end.never

        Billing::ZuoraPaypal.expects(:create_payment_method).returns({ success: true })


        target_details = {
          billed_on: zuora_user.billed_on.day,
          external_name: zuora_user.login,
          external_email: zuora_user.email,
          bt_fields: { user_id: zuora_user.id },
        }

        Billing::ZuoraPaypal.create_account(
          target_details: target_details,
          paypal_nonce: "fake-paypal-billing-agreement-nonce",
          billing_address: billing_address,
          vat_code: nil,
        )
      end
    end

    test "reports errors to Failbot when Braintree Customer fails to be created" do
      zuora_user = create(:user, billed_on: Date.parse("2018-10-17"))
      error = Braintree::ErrorResult.new(nil, { message: "Braintree error", errors: {} })
      Braintree::Customer.expects(:create).returns(error)
      Failbot.expects(:report).with(
        instance_of(Billing::CreateCustomer::BraintreeCreationError),
        has_entries({
          "gh.billing.braintree.response.message": "Braintree error",
        })
      ).once

      billing_address = {
        country_code_alpha3: "USA",
        region: "New York",
        postal_code: "10036",
      }
      target_details = {
        billed_on: zuora_user.billed_on.day,
        external_name: zuora_user.login,
        external_email: zuora_user.email,
        bt_fields: { user_id: zuora_user.id },
      }
      response = Billing::ZuoraPaypal.create_account(
        target_details: target_details,
        paypal_nonce: "fake-paypal-billing-agreement-nonce",
        billing_address: billing_address,
      )

      assert_equal false, response[:success]
    end
  end
end if GitHub.billing_enabled?
