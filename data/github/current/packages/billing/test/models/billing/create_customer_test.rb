# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateForUserTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::ZuoraTestHelper
  include GitHub::LoggerHelper
  include HydroTestHelpers

  setup do
    setup_currency_exchange
  end

  test "uses existing Customer and fills in payment details if no payment method exists" do
    user = create(:user)
    Billing::CreateCustomer.perform(user)

    VCR.use_cassette("braintree/successful_create_customer") do
      service = Billing::CreateCustomer.perform(
        user,
        details: encrypted_credit_card_params,
      )
      assert service.success?
      customer = user.reload.customer
      assert customer.zuora_account_id.present?
      assert customer_account = customer.customer_accounts.first
      assert customer_account.verified?
      assert_equal user, customer_account.user
      assert payment_method = customer.payment_method
      assert payment_method.persisted?
      assert payment_method.credit_card?
    end
  end

  test "suspends and spam-flags the user if the payment method is blacklisted" do
    user = create(:user)

    create :blacklisted_payment_method,
      unique_number_identifier: zuora_payment_method_number_identifier

    VCR.use_cassette("braintree/successful_create_customer") do
      Billing::CreateCustomer.perform(
        user,
        details: encrypted_credit_card_params,
      )
    end

    user.reload
    assert user.suspended?
    assert user.spammy?
    assert BlacklistedPaymentMethod.find_by(user_id: user.id).present?
  end

  test "locks billing and spam-flags the user if the payment method is blacklisted" do
    user = create(:user)
    enable_feature_flag(:enable_blocklist_consequence, user)
    enable_feature_flag(:check_should_disable_on_customer_creation, user)

    method = create :blacklisted_payment_method, :billing_locked,
      unique_number_identifier: zuora_payment_method_number_identifier

    VCR.use_cassette("braintree/successful_create_customer") do
      Billing::CreateCustomer.perform(
        user,
        details: encrypted_credit_card_params,
      )
    end

    user.reload
    refute user.suspended?
    assert user.disabled?
    assert user.disabled_reasons.include?(Billing::Public::BillingDisabledReasons::BlocklistedPaymentMethod.serialize)
    assert user.spammy?
    assert BlacklistedPaymentMethod.find_by(user_id: user.id).present?
  end

  test "associates an existing Zuora account with the specified org using the given Customer purpose" do
    org = create(:invoiced_organization)
    assert_nil org.sponsors_customer
    zuora_account_id = "2c92c0f96e63a4ee016e688d1cd53f7b"

    result = assert_difference(-> { Customer.count }) do
      with_live_zuora("zuora/sponsors_invoiced_account_positive_balance_no_payment_method") do
        Billing::CreateCustomer.perform(org, details: {
          zuora_account_id: zuora_account_id,
          omit_billing_info: true,
        }, purpose: :sponsors)
      end
    end

    assert_predicate result, :success?
    sponsors_customer = Customer.last
    assert_predicate sponsors_customer, :sponsors_purpose?
    assert_equal sponsors_customer, org.reload.sponsors_customer
    assert_equal zuora_account_id, T.must(sponsors_customer).zuora_account_id
    assert_equal "A0100394109", T.must(sponsors_customer).zuora_account_number
  end

  test "will not associate a nonexistent Zuora account with the specified org" do
    org = create(:invoiced_organization)
    assert_nil org.sponsors_customer
    invalid_zuora_account_id = "66170868"

    result = assert_no_difference(-> { Customer.count }) do
      with_live_zuora("zuora/successful_update_credit_card") do
        Billing::CreateCustomer.perform(org, details: {
          zuora_account_id: invalid_zuora_account_id,
          omit_billing_info: true,
        }, purpose: :sponsors)
      end
    end

    refute_predicate result, :success?
    assert_equal "HTTP 404", result.error_message
    assert_nil org.reload.sponsors_customer
  end

  test "suspend publishes abuse classification hydro event" do
    now = Time.parse("2018-01-01")

    Timecop.freeze(now) do
      user = create(:user)

      create :blacklisted_payment_method,
        unique_number_identifier: zuora_payment_method_number_identifier

      VCR.use_cassette("braintree/successful_create_customer") do
        Billing::CreateCustomer.perform(user, details: encrypted_credit_card_params)
      end

      message = {
        request_context: nil,
        actor: nil,
        account: Hydro::EntitySerializer.user(user),
        previous_classification: :NONE,
        current_classification: :SPAMMY,
        previous_spammy_reason: { value: "" },
        current_spammy_reason: { value: "Blacklisted payment method [octocat approved]" },
        previously_suspended: { value: false },
        currently_suspended: { value: true },
        currently_deleted: { value: false },
        origin: :DOTCOM,
        queue_action: :QUEUE_ACTION_NONE,
        queue_entry: nil,
        previous_queue: nil,
        current_queue: nil,
        queued_time_in_seconds: nil,
      }

      assert_hydro_published(message, schema: "github.v1.AbuseClassification")
      assert_hydro_messages count: 1, schema: "github.v1.AbuseClassification"
    end
  end

  test "prevents creation of Customer if the user looks spammy" do
    user = create(:user)
    user.stubs(:spammy?).returns(true)
    response = Billing::CreateCustomer.perform(user, details: encrypted_credit_card_params).response
    assert response.failed?
    assert_match /This account has been flagged. #{GitHub.support_link_text} for further information./, response.error_message
  end

  test "attach pre-existing payment method" do
    user = create(:user)
    @payment = create :payment_method, user: user

    VCR.use_cassette("braintree/successful_create_customer") do
      service = Billing::CreateCustomer.perform(user, details: encrypted_credit_card_params)
      assert service.success?


      assert @payment, service.customer.payment_method
      assert @payment.reload.persisted?
      assert @payment.credit_card?
    end
  end

  test "creates a customer without payment details" do
    user = create(:user)

    service = Billing::CreateCustomer.perform(user)

    assert service.success?

    customer = service.customer
    assert customer.valid?
    assert user.reload.customer
  end

  test "creates a billing locked customer for users that should be disabled" do
    enable_feature_flag(:billing_initialize_customer_locked_at)
    user = create(:user, billing_attempts: 3)

    service = Billing::CreateCustomer.perform(user)

    assert service.success?

    customer = service.customer
    assert customer.valid?
    assert user.reload.customer
    assert customer.locked_at
  end

  test "unlocks billing for a disabled user" do
    user = create :credit_card_user, billing_attempts: 15
    user.disable!

    VCR.use_cassette("braintree/successful_create_customer") do
      service = Billing::CreateCustomer.perform(user, details: encrypted_credit_card_params)
      assert service.success?

      user.reload

      assert_predicate user, :enabled?
      assert_equal 0, user.billing_attempts
    end
  end

  test "creates customer for businesses without zuora details" do
    business = create(:business, customer: nil)

    service = Billing::CreateCustomer.perform(business)

    assert service.success?
    customer = business.reload.customer
    refute customer.zuora_account_id
    refute customer.zuora_account_number
  end

  test "creates a billing locked customer for businesses that should be disabled" do
    enable_feature_flag(:billing_initialize_customer_locked_at)
    business = create(:business, customer: nil, trial_expires_at: GitHub::Billing.yesterday)

    service = Billing::CreateCustomer.perform(business)

    assert service.success?

    customer = service.customer
    assert customer.valid?
    assert business.reload.customer
    assert customer.locked_at
  end

  # TODO: This is a private method tested through send.
  # We could extract this into a separate class to test a public API of it but still used within
  # the private context of the CreateCustomer class
  context "#bill_to_contact" do
    test "uses the org's screening profile's first and last name if the entity name is empty" do
      profile = create(:account_screening_profile, entity_name: "")
      service = zuora_successful_customer_account_creation(profile.owner)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal profile.first_name, bill_to_contact[:firstName]
      assert_equal profile.last_name, bill_to_contact[:lastName]
    end

    test "Uses the business name as the bill to contact name" do
      profile = create(:account_screening_profile, :with_business, entity_name: "GitHub Labs LTD")
      zuora_business = profile.business

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_business)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal "GitHub", bill_to_contact[:firstName]
      assert_equal "Labs LTD", bill_to_contact[:lastName]
    end

    test "Uses the orgs business name as the bill to contact name" do
      profile = create(:account_screening_profile, :with_business, entity_name: "GitHub Labs LTD")
      zuora_org = create(:organization)
      zuora_org.business = profile.business
      zuora_org.save!

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_org)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal "GitHub", bill_to_contact[:firstName]
      assert_equal "Labs LTD", bill_to_contact[:lastName]
    end

    test "Uses a users full name as the bill to contact name" do
      zuora_user = create(:user)
      profile = create(:account_screening_profile, owner: zuora_user)

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_user)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal profile.first_name, bill_to_contact[:firstName]
      assert_equal profile.last_name, bill_to_contact[:lastName]
    end

    test "Uses a user-owned org's billing full name as the bill to contact name" do
      zuora_org = create(:organization)
      zuora_org.terms_of_service.update(type: "Standard", actor: zuora_org.admin)
      profile = create(:account_screening_profile, owner: zuora_org.admin)
      assert zuora_org.admin.link_trade_screening_record_to_org(organization: zuora_org)

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_org)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal profile.first_name, bill_to_contact[:firstName]
      assert_equal profile.last_name, bill_to_contact[:lastName]
    end

    test "Uses an CToS org entity name as the bill to contact name" do
      zuora_org = create(:organization)
      zuora_org.terms_of_service.update(type: "Corporate", actor: zuora_org.admin)
      profile = create(:account_screening_profile, :with_org, owner: zuora_org, entity_name: "GitHub Labs LTD")

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_org)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal "GitHub", bill_to_contact[:firstName]
      assert_equal "Labs LTD", bill_to_contact[:lastName]
    end

    test "Uses the business name as the bill to contact name if the business has no profile" do
      zuora_business = create(:business)

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_business)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal zuora_business.name, bill_to_contact[:firstName]
      assert_equal zuora_business.name, bill_to_contact[:lastName]
    end

    test "Uses the orgs business name as the bill to contact name if the business has no profile" do
      zuora_org = create(:organization)
      zuora_org.business = create(:business)
      zuora_org.save!

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_org)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal zuora_org.business.name, bill_to_contact[:firstName]
      assert_equal zuora_org.business.name, bill_to_contact[:lastName]
    end

    test "Uses a users login as the bill to contact name if the user has no profile" do
      zuora_user = create(:user)

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_user)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal zuora_user.login, bill_to_contact[:firstName]
      assert_equal zuora_user.login, bill_to_contact[:lastName]
    end

    test "Uses the orgs login as the bill to contact name if the org has no profile" do
      zuora_org = create(:organization)

      # Create the test customer account using VCR without actually contacting Zuora
      service = zuora_successful_customer_account_creation(zuora_org)
      assert service.success?

      bill_to_contact = service.send(:bill_to_contact)
      assert_equal zuora_org.login, bill_to_contact[:firstName]
      assert_equal zuora_org.login, bill_to_contact[:lastName]
    end
  end

  context "Zuora subscriptions" do
    test "sets tax exemption to 'No' for users without a tax exemption status" do
      user = create(:user)

      GitHub.zuorest_client.expects(:create_account).with do |params|
        params[:taxInfo][:exemptStatus] == "No"
      end.returns({
        "success" => true,
        "accountId" => "2c92c0f96f7b3b7e016f7b3f1b7b0000",
        "accountNumber" => "A00000001",
      })

      result = Billing::CreateCustomer.perform(
        user,
        actor: user,
        details: {
          omit_billing_info: true,
        }
      )

      assert result.success?
    end

    test "sets tax exemption to 'No' for orgs with a customer record and no tax exemption status" do
      org = create(:no_credit_card_org)

      GitHub.zuorest_client.expects(:create_account).with do |params|
        params[:taxInfo][:exemptStatus] == "No"
      end.returns({
        "success" => true,
        "accountId" => "2c92c0f96f7b3b7e016f7b3f1b7b0000",
        "accountNumber" => "A00000001",
      })

      result = Billing::CreateCustomer.perform(
        org,
        actor: org,
        details: {
          omit_billing_info: true,
        }
      )

      assert result.success?
    end

    test "sets tax exemption to 'No' for orgs with a customer record and a rejected tax exemption status" do
      org = create(:no_credit_card_org)
      create(:tax_exemption_status, customer: org.customer, status: :rejected, status_reason: "Some reason")

      GitHub.zuorest_client.expects(:create_account).with do |params|
        params[:taxInfo][:exemptStatus] == "No"
      end.returns({
        "success" => true,
        "accountId" => "2c92c0f96f7b3b7e016f7b3f1b7b0000",
        "accountNumber" => "A00000001",
      })

      result = Billing::CreateCustomer.perform(
        org,
        actor: org,
        details: {
          omit_billing_info: true,
        }
      )

      assert result.success?
    end

    test "sets tax exemption to 'Yes' for orgs with a customer record and an approved tax exemption status" do
      org = create(:no_credit_card_org)
      create(:tax_exemption_status, customer: org.customer, status: :approved)

      GitHub.zuorest_client.expects(:create_account).with do |params|
        params[:taxInfo][:exemptStatus] == "Yes"
      end.returns({
        "success" => true,
        "accountId" => "2c92c0f96f7b3b7e016f7b3f1b7b0000",
        "accountNumber" => "A00000001",
      })

      result = Billing::CreateCustomer.perform(
        org,
        actor: org,
        details: {
          omit_billing_info: true,
        }
      )

      assert result.success?
    end

    context "for businesses" do
      test "create a payment method for a credit card" do
        zuora_org = create(:organization)
        zuora_org.business = create(:business, name: "Streich-Haley")
        zuora_org.save!

        zuora_payment_method_id = zuora_parsed_payment_details[:zuora_payment_method_id]

        service = zuora_successful_customer_account_creation(zuora_org)
        assert service.success?

        with_live_zuora("zuora_subscription/successful_create_account_for_business_with_card") do
          customer = zuora_org.business.reload.customer
          zuora_account = customer.zuora_account
          zuora_customer_info = zuora_account.body["basicInfo"]
          assert customer.valid?
          assert_equal zuora_account.id, customer.zuora_account_id
          assert_equal zuora_customer_info["accountNumber"], customer.zuora_account_number

          zuora_bill_to_info = zuora_account.body["billToContact"]
          assert_equal zuora_org.business.name, zuora_bill_to_info["firstName"]
          assert_equal zuora_org.business.name, zuora_bill_to_info["lastName"]
          assert_equal zuora_org.business.name, zuora_customer_info["name"]

          assert_equal "Batch10", zuora_customer_info["batch"]
          assert_equal "No", zuora_customer_info["SynctoNetSuite__NS"]
          assert_equal "Self-Serve", zuora_customer_info["BusinessSegment__c"]
          assert_equal GitHub.zuora_self_serve_communication_profile_id, zuora_customer_info["communicationProfileId"]

          tax_info = zuora_account.body["taxInfo"]
          assert tax_info.present?
          assert_equal "Yes", tax_info["exemptStatus"]
          assert_equal "N/A", tax_info["exemptCertificateId"]

          payment_method = customer.payment_method.reload
          assert payment_method.persisted?
          assert payment_method.credit_card?
          assert payment_method.unique_number_identifier
          assert_equal "zuora", payment_method.payment_processor_type
          assert_equal zuora_payment_method_id, payment_method.payment_token
          assert_equal zuora_account.id, payment_method.payment_processor_customer_id
          assert_nil payment_method.paypal_email
        end
      end

      test "creates a customer and payment method for a paypal account" do
        events = subscribe "payment_method.create"

        org_admin = create(:user)
        zuora_org = create(:organization, admin: org_admin)
        zuora_org.business = create(:business)
        zuora_business = zuora_org.business
        zuora_org.save!

        billing_address = {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        }
        zuora_account_id = "zuora-account-id"
        zuora_payment_method_id = "payment-method-id"
        zuora_account_number = "A123456789"

        target_details = {
          billed_on: (zuora_business.billing_term_ends_on + 1.day).day,
          external_name: zuora_business.name,
          bt_fields: {},
        }
        Billing::ZuoraPaypal.expects(:create_account).with(
          target_details: target_details,
          paypal_nonce: "ABC123",
          billing_address: billing_address,
          vat_code: nil,
          tax_exemption_status: nil,
        ).returns({
          success: true,
          paypal_account: stub("Braintree Paypal Object", email: "zuora-buyer@github.com"),
          account_id: zuora_account_id,
          account_number: zuora_account_number,
          payment_method_id: zuora_payment_method_id,
        })

        service = Billing::CreateCustomer.perform(zuora_org, details: {
          paypal_nonce: "ABC123",
          billing_address: billing_address,
        }, actor: org_admin)

        assert service.success?

        customer = service.customer
        payment_method = customer.payment_method&.reload
        assert customer.valid?
        assert payment_method.paypal?
        assert customer.zuora_account_id.present?
        assert_equal zuora_account_id, payment_method.payment_processor_customer_id
        assert_equal zuora_payment_method_id, payment_method.payment_token
        assert_equal "zuora", payment_method.payment_processor_type

        expected_payload = {
          business: zuora_business.slug,
          business_id: zuora_business.id,
          actor: org_admin.login,
          actor_id: org_admin.id,
          note: "Created PayPal account",
          payment_processor_customer_id: zuora_account_id,
          payment_processor_type: "zuora",
          payment_method: "paypal",
          payment_method_id: payment_method.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    context "for users and orgs" do
      test "when enabled create a payment method for a credit card" do
        zuora_user = create(:user)
        zuora_payment_method_id = "2c92c0f962cec7990162d46ead5e4c09"
        service = zuora_successful_customer_account_creation(zuora_user)
        assert service.success?

        with_live_zuora("zuora_subscription/successful_create_account_with_card") do
          customer = zuora_user.reload.customer
          zuora_account = customer.zuora_account
          zuora_customer_info = zuora_account.body["basicInfo"]
          assert customer.valid?
          assert_equal zuora_account.id, customer.zuora_account_id
          assert_equal zuora_customer_info["accountNumber"], customer.zuora_account_number

          assert_equal "Batch10", zuora_customer_info["batch"]
          assert_equal "No", zuora_customer_info["SynctoNetSuite__NS"]
          assert_equal "Self-Serve", zuora_customer_info["BusinessSegment__c"]
          assert_equal GitHub.zuora_self_serve_communication_profile_id, zuora_customer_info["communicationProfileId"]

          tax_info = zuora_account.body["taxInfo"]
          assert tax_info.present?
          assert_equal "Yes", tax_info["exemptStatus"]
          assert_equal "N/A", tax_info["exemptCertificateId"]

          customer_account = customer.customer_accounts.first
          assert customer_account.verified?
          assert_equal zuora_user, customer_account.user

          payment_method = customer.payment_method.reload
          assert payment_method.persisted?
          assert payment_method.credit_card?
          assert payment_method.unique_number_identifier
          assert_equal "zuora", payment_method.payment_processor_type
          assert_equal zuora_payment_method_id, payment_method.payment_token
          assert_equal zuora_account.id, payment_method.payment_processor_customer_id
          assert_nil payment_method.paypal_email
        end
      end

      test "returns false if Braintree Customer creation fails" do
        user = create(:user)

        payment_details = {
          zuora_payment_method_id: "2c92c0f962cec7990162d46ead5e4c09",
          billing_address: {
            country_code_alpha3: "USA",
            region: "NC",
            postal_code: "10036",
          },
          vat_code: "",
        }
        Braintree::Customer.expects(:create).returns(Braintree::ErrorResult.new(nil, errors: {}))

        Billing::Platform::Api::Client.any_instance
          .stubs(:create_or_update_customer)
          .returns({})
        Failbot.expects(:report)
        result = VCR.use_cassette("zuora_subscription/successful_create_account_with_card") do
          Billing::CreateCustomer.perform(user, details: payment_details)
        end

        refute result.success?
      end

      test "fails to create a customer with U.S address and no state" do
        user = create(:user)

        payment_details = {
          zuora_payment_method_id: "2c92c0f96469402501646c0be9ed6939",
          billing_address: {
            country_code_alpha3: "USA",
            region: nil,
            postal_code: "10036",
          },
          vat_code: "",
        }
        result = with_live_zuora("zuora_subscription/failure_create_account_with_u_s_address_no_state") do
          Billing::CreateCustomer.perform(user, details: payment_details)
        end

        refute result.success?
        assert_match(/State is required/, result.error_message)
      end

      test "provides address validation when billing_address is nil" do
        user = create(:user)

        payment_details = {
          zuora_payment_method_id: "2c92c0f97a183a5f017a1b74136058ff",
          billing_address: nil,
          vat_code: "",
        }
        result = with_live_zuora("zuora_subscription/failure_create_account_with_no_billing_data") do
          Billing::CreateCustomer.perform(user, details: payment_details)
        end

        refute result.success?
        assert_match(/Country is a required field/, result.error_message)
      end

      test "suspends and spam-flags the user if the payment method is blacklisted" do
        user = create(:user)

        # Unique number identifier was received from Braintree and
        # recorded in the VCR tape zuora_successful_customer_account_creation
        payment_method_unique_number_identifier = "753546e62855075ee4522b4137b83f02"
        create(:blacklisted_payment_method, unique_number_identifier: payment_method_unique_number_identifier)

        zuora_successful_customer_account_creation(user)
        user.reload

        assert user.suspended?
        assert user.spammy?
        assert BlacklistedPaymentMethod.find_by(user_id: user.id).present?
      end

      test "creates a customer and payment method for a paypal account" do
        events = subscribe "payment_method.create"

        zuora_user = create(:user, billed_on: GitHub::Billing.today)

        billing_address = {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        }
        zuora_account_id = "zuora-account-id"
        zuora_payment_method_id = "payment-method-id"
        zuora_account_number = "A123456789"

        target_details = {
          billed_on: zuora_user.billed_on.day,
          external_name: zuora_user.login,
          bt_fields: { user_id: zuora_user.id },
        }
        Billing::ZuoraPaypal.expects(:create_account).with(
          target_details: target_details,
          paypal_nonce: "ABC123",
          billing_address: billing_address,
          vat_code: nil,
          tax_exemption_status: nil,
        ).returns({
          success: true,
          paypal_account: stub("Braintree Paypal Object", email: "zuora-buyer@github.com"),
          account_id: zuora_account_id,
          account_number: zuora_account_number,
          payment_method_id: zuora_payment_method_id,
        })

        service = Billing::CreateCustomer.perform(zuora_user, actor: zuora_user, details: {
          paypal_nonce: "ABC123",
          billing_address: billing_address,
        })

        assert service.success?

        customer = service.customer
        payment_method = customer.payment_method&.reload
        assert customer.valid?
        assert payment_method.paypal?
        assert customer.zuora_account_id.present?
        assert_equal zuora_account_id, payment_method.payment_processor_customer_id
        assert_equal zuora_payment_method_id, payment_method.payment_token
        assert_equal "zuora", payment_method.payment_processor_type

        expected_payload = {
          user: zuora_user.login,
          user_id: zuora_user.id,
          actor: zuora_user.login,
          actor_id: zuora_user.id,
          note: "Created PayPal account",
          payment_processor_customer_id: zuora_account_id,
          payment_processor_type: "zuora",
          payment_method: "paypal",
          payment_method_id: payment_method.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end

      test "logs billing customer creation" do
        user = create(:user)

        payment_details = {
          zuora_payment_method_id: "2c92c0f962cec7990162d46ead5e4c09",
          billing_address: {
            country_code_alpha3: "USA",
            region: "NC",
            postal_code: "10036",
          },
          vat_code: "",
        }

        Braintree::Customer.expects(:create).returns(stub({ success?: true }))
        Billing::Platform::Api::Client.any_instance.stubs(:create_or_update_customer).returns({})
        payment_method = Billing::Zuora::PaymentMethod.new(
          "CreditCardMaskNumber" => "************1111",
          "CreditCardExpirationMonth" => 12,
          "CreditCardExpirationYear" => 2024,
          "CreditCardType" => "Visa",
        )
        payment_method.stubs(:fingerprint).returns("fingerprint")
        Billing::Zuora::PaymentMethod.expects(:find).returns(payment_method)
        Zuorest::RestClient.any_instance.stubs(:create_account)
          .returns({
            "success" => true,
            "accountNumber" => "A00000001",
            "accountId" => "1",
            "paymentMethodId" => "2c92c0f962cec7990162d46ead5e4c09",
          })

        expected_log = {
          "code.namespace" => "Billing::CreateCustomer",
          "code.function" => "create_remote_customer",
          "gh.billing.billable_entity.id" => user.id,
          "gh.billing.billable_entity.type" => user.class.name,
        }
        log_output = capture_logs do
          assert_logged(**expected_log) do
            result = Billing::CreateCustomer.perform(user, details: payment_details)
            assert result.success?
          end
        end

        assert_includes log_output, { paymentGateway: "Stripe v3" }.inspect[1..-2].inspect[1..-2]
        assert_includes log_output, { APM__c: "True" }.inspect[1..-2].inspect[1..-2]
        assert_includes log_output, { BusinessSegment__c: "Self-Serve" }.inspect[1..-2].inspect[1..-2]
      end
    end

    context "for enterprise accounts" do
      test "create a payment method for a credit card" do
        zuora_business = create(:business, name: "Streich-Haley")
        zuora_payment_method_id = zuora_parsed_payment_details[:zuora_payment_method_id]
        service = zuora_successful_customer_account_creation(zuora_business)
        assert service.success?

        with_live_zuora("zuora_subscription/successful_create_account_for_business_with_card") do
          customer = zuora_business.reload.customer
          zuora_account = customer.zuora_account
          zuora_customer_info = zuora_account.body["basicInfo"]
          assert customer.valid?
          assert_equal zuora_account.id, customer.zuora_account_id
          assert_equal zuora_customer_info["accountNumber"], customer.zuora_account_number

          zuora_bill_to_info = zuora_account.body["billToContact"]
          assert_equal zuora_business.name, zuora_bill_to_info["firstName"]
          assert_equal zuora_business.name, zuora_bill_to_info["lastName"]
          assert_equal zuora_business.name, zuora_customer_info["name"]

          assert_equal "Batch10", zuora_customer_info["batch"]
          assert_equal "No", zuora_customer_info["SynctoNetSuite__NS"]
          assert_equal "Self-Serve", zuora_customer_info["BusinessSegment__c"]
          assert_equal GitHub.zuora_self_serve_communication_profile_id, zuora_customer_info["communicationProfileId"]

          tax_info = zuora_account.body["taxInfo"]
          assert tax_info.present?
          assert_equal "Yes", tax_info["exemptStatus"]
          assert_equal "N/A", tax_info["exemptCertificateId"]

          payment_method = customer.payment_method.reload
          assert payment_method.persisted?
          assert payment_method.credit_card?
          assert payment_method.unique_number_identifier
          assert_equal "zuora", payment_method.payment_processor_type
          assert_equal zuora_payment_method_id, payment_method.payment_token
          assert_equal zuora_account.id, payment_method.payment_processor_customer_id
          assert_nil payment_method.paypal_email
        end
      end

      test "create a payment method for PayPal" do
        events = subscribe "payment_method.create"

        admin = create(:user)
        zuora_business = create(:business, name: "Streich-Haley", owners: [admin])
        billing_address = {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        }
        zuora_account_id = "zuora-account-id"
        zuora_payment_method_id = "payment-method-id"
        zuora_account_number = "A123456789"

        target_details = {
          billed_on: (zuora_business.billing_term_ends_on + 1.day).day,
          external_name: zuora_business.slug,
          bt_fields: {},
        }
        Billing::ZuoraPaypal.expects(:create_account).with(
          target_details: target_details,
          paypal_nonce: "ABC123",
          billing_address: billing_address,
          vat_code: nil,
          tax_exemption_status: nil,
        ).returns({
          success: true,
          paypal_account: stub("Braintree Paypal Object", email: "zuora-buyer@github.com"),
          account_id: zuora_account_id,
          account_number: zuora_account_number,
          payment_method_id: zuora_payment_method_id,
        })

        service = Billing::CreateCustomer.perform(zuora_business, details: {
          paypal_nonce: "ABC123",
          billing_address: billing_address,
        }, actor: admin)

        assert service.success?

        customer = service.customer
        payment_method = customer.payment_method&.reload
        assert customer.valid?
        assert payment_method.paypal?
        assert customer.zuora_account_id.present?
        assert_equal zuora_account_id, payment_method.payment_processor_customer_id
        assert_equal zuora_payment_method_id, payment_method.payment_token
        assert_equal "zuora", payment_method.payment_processor_type

        expected_payload = {
          business: zuora_business.slug,
          business_id: zuora_business.id,
          actor: admin.login,
          actor_id: admin.id,
          note: "Created PayPal account",
          payment_processor_customer_id: zuora_account_id,
          payment_processor_type: "zuora",
          payment_method: "paypal",
          payment_method_id: payment_method.id,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end

      test "change enterprise billing method from credit card to PayPal" do
        admin = create(:user)
        zuora_business = create(:business, name: "Streich-Haley", slug: "Streich-Haley",
          owners: [admin], billing_email: "zuora-buyer@github.com",
          customer: create(:customer, name: "Streich-Haley", billing_end_date: 1.year.from_now))
        zuora_payment_method_id = zuora_parsed_payment_details[:zuora_payment_method_id]
        service = zuora_successful_customer_account_creation(zuora_business)

        assert service.success?
        customer = service.customer
        payment_method = customer.payment_method&.reload

        assert payment_method.credit_card?

        billing_address = {
          country_code_alpha3: "USA",
          region: "New York",
          postal_code: "10036",
        }
        zuora_account_id = "zuora-account-id"
        zuora_payment_method_id = "payment-method-id"
        zuora_account_number = "A123456789"

        target_details = {
          billed_on: (zuora_business.billing_term_ends_on + 1.day).day,
          external_name: zuora_business.slug,
          bt_fields: {},
        }
        Billing::ZuoraPaypal.expects(:create_account).with(
          target_details: target_details,
          paypal_nonce: "ABC123",
          billing_address: billing_address,
          vat_code: nil,
          tax_exemption_status: nil,
        ).returns({
          success: true,
          paypal_account: stub("Braintree Paypal Object", email: "zuora-buyer@github.com"),
          account_id: zuora_account_id,
          account_number: zuora_account_number,
          payment_method_id: zuora_payment_method_id,
        })

        service = Billing::CreateCustomer.perform(zuora_business, details: {
          paypal_nonce: "ABC123",
          billing_address: billing_address,
        }, actor: admin)
        assert service.success?

        customer = service.customer
        payment_method = customer.payment_method&.reload
        assert payment_method.paypal?
      end

      test "returns false if Braintree Customer creation fails" do
        zuora_business = create(:business, name: "Streich-Haley")

        payment_details = {
          zuora_payment_method_id: "2c92c0f962cec7990162d46ead5e4c09",
          billing_address: {
            country_code_alpha3: "USA",
            region: "NC",
            postal_code: "10036",
          },
          vat_code: "",
        }
        Braintree::Customer.expects(:create).returns(Braintree::ErrorResult.new(nil, errors: {}))
        Failbot.expects(:report)
        Billing::Platform::Api::Client.any_instance
          .stubs(:create_or_update_customer)
          .returns({})

        result = with_live_zuora("zuora_subscription/successful_create_account_for_business_with_card") do
          Billing::CreateCustomer.perform(zuora_business, details: payment_details)
        end

        refute result.success?
      end
    end
  end

  if GitHub.sponsors_enabled?
    test "creates a Sponsors-specific customer without billing information" do
      org_admin = create(:user)
      org = create(:invoiced_organization, admin: org_admin, login: "testorg-69f36eee13f1dbef") # see VCR cassette
      org.stubs(:recurring_charge) # don't create or sync subscription
      assert_nil org.sponsors_customer

      with_live_zuora("zuora_subscription/successful_create_sponsorship_account_without_card") do
        result = assert_difference(-> { Customer.count }) do
          ::Billing::CreateCustomer.perform(org, actor: org_admin, details: { omit_billing_info: true },
            purpose: :sponsors)
        end

        assert_predicate result, :success?

        sponsors_customer = Customer.sponsors_purpose.last
        sponsors_customer = T.must(sponsors_customer)
        refute_nil sponsors_customer
        assert_equal org.login, sponsors_customer.name
        assert_predicate sponsors_customer, :zuora?
        assert_predicate sponsors_customer, :invoiced?
        assert_predicate sponsors_customer, :valid?
        assert_equal sponsors_customer, org.reload.sponsors_customer

        zuora_account = sponsors_customer.zuora_account
        zuora_account = T.must(zuora_account)
        assert_equal zuora_account.id, sponsors_customer.zuora_account_id

        zuora_customer_info = zuora_account.body["basicInfo"]
        assert_equal "#{org} for sponsorships", zuora_customer_info["name"]
        assert_equal zuora_customer_info["accountNumber"], sponsors_customer.zuora_account_number

        assert_equal "Batch10", zuora_customer_info["batch"]
        assert_equal "No", zuora_customer_info["SynctoNetSuite__NS"]
        assert_equal "Corporate-Sponsors", zuora_customer_info["BusinessSegment__c"]
        assert_equal GitHub.zuora_self_serve_communication_profile_id, zuora_customer_info["communicationProfileId"]

        tax_info = zuora_account.body["taxInfo"]
        assert tax_info.present?
        assert_equal "Yes", tax_info["exemptStatus"]
        assert_equal "N/A", tax_info["exemptCertificateId"]

        assert_equal 1, sponsors_customer.customer_accounts.count
        customer_account = sponsors_customer.customer_accounts.first
        assert_predicate customer_account, :verified?
        assert_equal org, T.must(customer_account).user
        assert_predicate customer_account, :sponsors_purpose?

        payment_method = org.sponsors_payment_method
        refute_nil payment_method
        assert_equal sponsors_customer.zuora_account_id, payment_method.payment_processor_customer_id
        assert_equal PaymentMethod::PAYMENT_TOKEN_CLEARED, payment_method.payment_token
      end
    end

    # https://github.com/github/sponsors/issues/3518
    test "retains general payment method when creating a sponsors-purpose customer" do
      org_admin = create(:user)
      org = create(:credit_card_org, admin: org_admin, login: "testorg-69f36eee13f1dbef") # see VCR cassette
      org.stubs(:recurring_charge) # don't create or sync subscription
      payment_method = org.payment_method

      assert payment_method.present?
      assert_nil org.sponsors_customer

      with_live_zuora("zuora_subscription/successful_create_sponsorship_account_without_card") do
        result = assert_difference(["Customer.count", "PaymentMethod.count"]) do
          ::Billing::CreateCustomer.perform(org, actor: org_admin, details: { omit_billing_info: true },
            purpose: :sponsors)
        end

        assert_predicate result, :success?

        assert_equal payment_method, org.reload.payment_method
        sponsors_payment_method = org.sponsors_payment_method
        refute_nil sponsors_payment_method
        assert_nil sponsors_payment_method.card_type
      end
    end

    # https://github.com/github/sponsors/issues/4045
    test "creates a sponsors-purpose customer for an enterprise-linked org" do
      org_admin = create(:user)
      org = create(:enterprise_linked_org, admin: org_admin, login: "testorg-69f36eee13f1dbef") # see VCR cassette

      assert_nil org.customer
      assert_nil org.payment_method
      assert_nil org.sponsors_customer

      with_live_zuora("zuora_subscription/successful_create_sponsorship_account_without_card") do
        result = assert_difference(["Customer.count", "PaymentMethod.count"]) do
          ::Billing::CreateCustomer.perform(org, actor: org_admin, details: { omit_billing_info: true },
            purpose: :sponsors)
        end

        assert_predicate result, :success?
        assert_nil org.reload.customer
        assert_nil org.payment_method
        assert org.sponsors_payment_method
        assert org.sponsors_customer
      end
    end
  end

  context "Apple iap subscriptions" do
    test "creates a customer with no billing information" do
      zuora_user = create(:user, login: "user-4ea99d564843128047f8528b") # see VCR cassette
      service = zuora_successful_customer_account_creation(zuora_user, { omit_billing_info: true })
      assert service.success?

      with_live_zuora("zuora_subscription/successful_create_account_without_card") do
        customer = zuora_user.reload.customer
        zuora_account = customer.zuora_account
        zuora_customer_info = zuora_account.body["basicInfo"]
        refute_predicate customer, :invoiced?
        assert customer.valid?
        assert_equal zuora_account.id, customer.zuora_account_id
        assert_equal zuora_customer_info["accountNumber"], customer.zuora_account_number
        assert_equal zuora_user.login, zuora_customer_info["name"]

        assert_equal "Batch10", zuora_customer_info["batch"]
        assert_equal "No", zuora_customer_info["SynctoNetSuite__NS"]
        assert_equal "Self-Serve", zuora_customer_info["BusinessSegment__c"]
        assert_equal GitHub.zuora_self_serve_communication_profile_id, zuora_customer_info["communicationProfileId"]

        tax_info = zuora_account.body["taxInfo"]
        assert tax_info.present?
        assert_equal "Yes", tax_info["exemptStatus"]
        assert_equal "N/A", tax_info["exemptCertificateId"]

        customer_account = customer.customer_accounts.first
        assert customer_account.verified?
        assert_equal zuora_user, customer_account.user

        refute_nil customer.payment_method
        assert_equal customer.zuora_account_id, customer.payment_method.payment_processor_customer_id
        assert_equal customer.payment_method.payment_token, PaymentMethod::PAYMENT_TOKEN_CLEARED
      end
    end

    test "does not create a customer for a spammy user" do
      user = create(:user)
      user.stubs(:spammy?).returns(true)
      response = Billing::CreateCustomer.perform(user, details: { omit_billing_info: true }).response
      assert response.failed?
      assert_match /This account has been flagged. #{GitHub.support_link_text} for further information./, response.error_message
    end

    test "returns false if the Zuora account creation fails" do
      user = create(:user)

      GitHub.zuorest_client.expects(:create_account).returns({
        success: false,
        processId: "6E9E19BE471A4F2F",
        reasons: [{
          code: 51001122,
          message: "'billToContact' may not be null"
        }]
      })
      result = Billing::CreateCustomer.perform(user, details: { omit_billing_info: true })

      refute result.success?
    end
  end

  context "zuora account's bill cycle day" do
    test "zuora account's bill cycle day shouldn't set to 1 if customer isn't billed_via_billing_platform" do
      customer = create(:customer, billed_via_billing_platform: false)
      user = create(:user, customer: customer)

      # Return success: false to avoid updates to the customer object
      GitHub.zuorest_client.expects(:create_account).with(has_entries(billCycleDay: 0)).returns(success: false)
      result = Billing::CreateCustomer.perform(user, details: { omit_billing_info: true })

      refute result.success?
    end

    test "zuora account's bill cycle day should set to 1 if customer is billed_via_billing_platform" do
      customer = create(:customer, billed_via_billing_platform: true)
      user = create(:user, customer: customer)

      # Return success: false to avoid updates to the customer object
      GitHub.zuorest_client.expects(:create_account).with(has_entries(billCycleDay: 1)).returns(success: false)
      result = Billing::CreateCustomer.perform(user, details: { omit_billing_info: true })

      refute result.success?
    end
  end

  context "customer creation state" do
    test "does not create an additional Zuora account if the customer is already in the process of being created" do
      user = create(:user)
      GitHub::Restraint.any_instance
        .expects(:lock!)
        .raises(GitHub::Restraint::UnableToLock)

      GitHub.zuorest_client.expects(:get_account).never
      GitHub.zuorest_client.expects(:create_account).never
      service = Billing::CreateCustomer.perform(user, details: encrypted_credit_card_params)
      refute service.success?
      assert_equal service.response.error_message, "Customer creation is already in progress"
      assert_dogstats_increment(1, "billing.multiple_customer_creation_requests")
    end
  end
end if GitHub.billing_enabled?
