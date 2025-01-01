# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::AccountTest < GitHub::BillingTestCase
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @zuora_account_id = "2c92c0f85cee08f6015d153382da58b4"
    @zuora_account_nunber = "A0100000181"
    @zuora_not_found_id = "2c92c0f85cee08f6015d153382da58b5"
    @billing_contact_id = "2c92c0f85cee08f6015d153382e058b5"
    @zuora_subscrition_id = "2c92c0f85cee0940015d154532e333d2"
  end

  setup do
    setup_currency_exchange
  end

  def zuorest_account_model(account_id:)
    with_live_zuora("zuora/get_account") do
      Zuorest::Model::Account.find(account_id)
    end
  end

  context ".find" do
    test "returns nil if no account ID is provided" do
      unstub_zuora

      Zuorest::Model::Account.expects(:find).never

      account = Billing::Zuora::Account.find(nil)

      assert_nil account
    end

    test "returns nil when zuora returns a 404" do
      account = with_live_zuora("zuora/get_account_not_found") do
        Billing::Zuora::Account.find(@zuora_not_found_id)
      end

      assert_nil account
    end

    test "returns an account object for the given account ID" do
      account = with_live_zuora("zuora/get_account") do
        Billing::Zuora::Account.find(@zuora_account_id)
      end

      assert_instance_of Billing::Zuora::Account, account
    end
  end

  context ".generate_billing_documents" do
    test "returns failure if zuora account number is not provided" do
      unstub_zuora

      Zuorest::Model::Account.expects(:generate_billing_documents).never

      billing_documents = T.must(Billing::Zuora::Account.generate_billing_documents(nil, nil, nil))

      refute billing_documents.success?
      assert_equal "zuora_account_number is not present", billing_documents.error
    end

    test "returns failure if zuora subscription id is not provided" do
      unstub_zuora

      Zuorest::Model::Account.expects(:generate_billing_documents).never

      billing_documents = T.must(Billing::Zuora::Account.generate_billing_documents(@zuora_account_nunber, nil, nil))

      refute billing_documents.success?
      assert_equal "zuora_subscription_id is not present", billing_documents.error
    end

    test "returns generated billing documents" do
      billing_documents = with_live_zuora("zuora/generate_billing_documents") do
        T.must(Billing::Zuora::Account.generate_billing_documents(@zuora_account_nunber, @zuora_subscrition_id,
          [Billing::Zuora::Account::BILLING_DOCUMENTS_CHARGE_TYPE_TO_EXCLUDE[:usage]]))
      end

      assert billing_documents.success?
      assert_equal [], billing_documents.zuora_result["invoices"]
    end
  end

  context "#partner_customer?" do
    test "return true when PartnerCustomer__c is 'Yes'" do
      account = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(
          :zuora_account,
          basicInfo: attributes_for(:zuora_account_basic_info, :partner_customer)
        ))
      )

      assert account.partner_customer?
    end

    test "return false when PartnerCustomer__c is 'No'" do
      account = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(
          :zuora_account,
          basicInfo: attributes_for(:zuora_account_basic_info)
        ))
      )

      refute account.partner_customer?
    end
  end

  context "#billing_contact" do
    test "returns a Sponsors::BillingContactResult with an error when no bill to id is provided" do
      unstub_zuora
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:billingAndPayment].merge!("billCycleDay" => 5)
      zuora_account[:billToContact].merge!("id" => nil)

      account = T.must(Billing::Zuora::Account.new(zuora_account))
      billing_contact = account.billing_contact

      expected_error_message = "BillToId must be present"
      assert_instance_of Sponsors::BillingContactResult, billing_contact
      assert_equal expected_error_message, billing_contact.error
    end

    test "returns a Sponsors::BillingContactResult with an error when zuora returns a 404" do
      unstub_zuora

      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:billToContact].merge!("id" => "BillToId")

      account = T.must(Billing::Zuora::Account.new(zuora_account))
      contact = with_live_zuora("zuora/object/get_contact_not_found") do
        account.billing_contact
      end

      expected_error_message = "HTTP 404"
      assert_instance_of Sponsors::BillingContactResult, contact
      assert_equal expected_error_message, contact.error
    end

    test "returns an account object for the given account ID" do
      account = with_live_zuora("zuora/object/get_account") do
        Billing::Zuora::Account.find(@zuora_account_id)
      end
      contact = with_live_zuora("zuora/object/get_contact") do
        account.billing_contact
      end
      customer_hash = contact.contact_data

      assert_instance_of Sponsors::BillingContactResult, contact
      assert_includes customer_hash.keys, "Address1"
      assert_includes customer_hash.keys, "Address2"
      assert_includes customer_hash.keys, "City"
      assert_includes customer_hash.keys, "Country"
      assert_includes customer_hash.keys, "FirstName"
      assert_includes customer_hash.keys, "LastName"
      assert_includes customer_hash.keys, "PostalCode"
      assert_includes customer_hash.keys, "State"
    end
  end

  context "#bill_cycle_day" do
    test "returns integer value for bill cycle day from the response from Zuora" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:billingAndPayment].merge!("billCycleDay" => 5)
      account = T.must(Billing::Zuora::Account.new(zuora_account))

      assert_equal 5, account.bill_cycle_day
    end
  end

  context "#credit_balance" do
    test "returns the credit balance in the Zuora account's currency" do
      with_live_zuora("zuora/sponsors_invoiced_account_positive_balance_no_payment_method") do
        account = T.must(Billing::Zuora::Account.find("2c92c0f96e63a4ee016e688d1cd53f7b"))
        assert_equal Billing::Money.new(5000_00, "USD"), account.credit_balance
      end
    end

    test "returns the credit balance in the default currency when none is set" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:metrics].merge!("creditBalance" => 1.1)

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      assert_equal Billing::Money.new(110, Billing::Money.default_currency), account.credit_balance
    end

    test "returns zero when there isn't a credit balance" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:metrics].merge!("creditBalance" => nil)

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      assert_equal Billing::Money.zero, account.credit_balance
    end
  end

  context "#apm_enabled?" do
    test "returns true for truthy strings" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => "true")

      account1 = T.must(Billing::Zuora::Account.new(zuora_account))
      assert_predicate account1, :apm_enabled?

      zuora_account[:basicInfo].merge!("APM__c" => "True")
      account2 = T.must(Billing::Zuora::Account.new(zuora_account))
      assert_predicate account2, :apm_enabled?
    end

    test "returns true for a true boolean value" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => true)

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      assert_predicate account, :apm_enabled?
    end

    test "returns false for stringified false values" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => "false")

      account1 = T.must(Billing::Zuora::Account.new(zuora_account))
      refute_predicate account1, :apm_enabled?

      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => "False")
      account2 = T.must(Billing::Zuora::Account.new(zuora_account))

      refute_predicate account2, :apm_enabled?
    end

    test "returns false for a false boolean value" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => false)

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      refute_predicate account, :apm_enabled?
    end

    test "returns false for nil values" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => nil)
      account = T.must(Billing::Zuora::Account.new(zuora_account))

      refute_predicate account, :apm_enabled?
    end

    test "returns false for invalid values" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:basicInfo].merge!("APM__c" => "invalid")

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      refute_predicate account, :apm_enabled?
    end
  end

  context "#payment_gateway" do
    test "returns the account's payment gateway" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:billingAndPayment].merge!(paymentGateway: Billing::Zuora::PaymentGateway::STRIPE_V3)

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      assert_equal account.payment_gateway, Billing::Zuora::PaymentGateway::STRIPE_V3
    end

    test "returns nil when no payment gateway is set" do
      zuora_account = zuorest_account_model(account_id: @zuora_account_id)
      zuora_account[:billingAndPayment].merge!(paymentGateway: nil)

      account = T.must(Billing::Zuora::Account.new(zuora_account))

      assert_nil account.payment_gateway
    end
  end
end if GitHub.billing_enabled?
