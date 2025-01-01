# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper
  include HydroTestHelpers
  include StringFromBinaryTestHelper

  fixtures do
    @customer = create :customer, billing_end_date: GitHub::Billing.today + 1.year
  end

  setup do
    @billing_platform_emission_enabled_event = "billing_customer.billing_platform_emission_enabled"
    @billing_platform_emission_disabled_event = "billing_customer.billing_platform_emission_disabled"
    @metered_via_azure_enabled_event = "billing_customer.metered_via_azure_enabled"
    @metered_via_azure_disabled_event = "billing_customer.metered_via_azure_disabled"
    @azure_subscription_linked_event = "billing_customer.azure_subscription_linked"
    @azure_subscription_unlinked_event = "billing_customer.azure_subscription_unlinked"

    @billed_via_billing_platform_stats_name = "billing_customer.billed_via_billing_platform"
    @metered_via_azure_stats_name = "billing_customer.metered_via_azure_change"
    @azure_subscription_stats_name = "billing_customer.azure_subscription_change"
  end

  context "with_zuora_account_id scope" do
    test "filters by the given Zuora account ID" do
      customer1 = create(:credit_card_customer)
      customer2 = create(:customer, :zuora_paypal)
      refute_equal customer1.zuora_account_id, customer2.zuora_account_id

      result = Customer.with_zuora_account_id(customer1.zuora_account_id)

      assert_equal [customer1], result
    end
  end

  context "metered_via_azure_not_allowed_for_users" do
    test "allows metered_via_azure for businesses" do
      customer = create(:customer, :zuora)
      create(:business, customer: customer)

      customer.metered_via_azure = true
      customer.azure_subscription_id = SecureRandom.uuid
      assert customer.valid?
    end

    test "allows metered_via_azure for organizations" do
      customer = create(:customer, :zuora)
      organization = create(:organization)
      create(:customer_account, user: organization, customer: customer)

      customer.metered_via_azure = true
      customer.azure_subscription_id = SecureRandom.uuid
      assert customer.valid?
    end

    test "does not allow metered_via_azure for users" do
      customer = create(:customer, :zuora)
      user = create(:user)
      create(:customer_account, user: user, customer: customer)
      customer.reload

      customer.metered_via_azure = true
      customer.azure_subscription_id = SecureRandom.uuid
      refute customer.valid?
      assert_equal ["cannot be true for customers associated with users"], customer.errors[:metered_via_azure]

      customer.metered_via_azure = false
      assert customer.valid?
    end
  end

  test "requires a name" do
    customer = Customer.new

    refute customer.save
    assert customer.errors[:name]
  end

  test "supports emoji for name" do
    encoded_value = "Much 😀"
    encoded_value2 = "Much #{GRIN_EMOJI}"
    customer = create :customer, name: encoded_value

    assert_predicate customer, :valid?
    assert_multibyte_tracked_changes(customer, :name, encoded_value, encoded_value2)
  end

  test "requires a billing_end_date if invoiced" do
    customer = Customer.new(
      name: "Cadgian & Scott LLC",
      billing_type: "invoice",
    )

    refute customer.valid?
    assert customer.errors[:billing_end_date]
  end

  test "billing_end_date should be within the accepted date range" do
    customer = build :customer,
      name: "Cadgian & Scott LLC",
      billing_type: "invoice",
      billing_end_date: 10_000_000.years.from_now

    refute customer.valid?
    assert_equal \
      ["is not within the supported date range"],
      customer.errors[:billing_end_date]
  end

  test "create sets external_uuid" do
    customer = Customer.new
    customer.name = "Acme, Incustomer."

    assert customer.save
    assert customer.external_uuid
  end

  test "update does not change external_uuid if external_uuid is present" do
    customer = Customer.new
    customer.name = "Acme, Incustomer."
    assert customer.save
    uuid = customer.external_uuid
    assert_predicate uuid, :present?

    assert customer.update name: "Changed name"
    assert_predicate customer, :valid?
    assert_equal uuid, customer.external_uuid
  end

  test "update sets external_uuid if external_uuid is blank" do
    customer = Customer.new
    customer.name = "Acme, Incustomer."
    assert customer.save
    customer.update_column(:external_uuid, "")
    assert_predicate customer.external_uuid, :blank?

    assert customer.update name: "Changed name"
    assert_predicate customer, :valid?
    assert_predicate customer.external_uuid, :present?
  end

  test "with parent customer" do
    parent = Customer.new
    parent.name = "Conglomorates, Incustomer."
    parent.save

    customer = Customer.new
    customer.name = "Acme, Incustomer."
    customer.parent_customer = parent

    assert customer.save
    assert_equal [customer], parent.child_customers
  end

  test "update credit card key is unique" do
    customer = create :customer
    assert_match /#{customer.id}/, customer.update_payment_method_key
  end

  context "#update_from_zuora" do
    test "updates the bill cycle day from Zuora" do
      new_bill_cycle_day = 15
      customer = create :customer, :zuora, bill_cycle_day: 1
      Billing::Zuora::Account.any_instance.stubs(:bill_cycle_day).returns(new_bill_cycle_day)

      customer.update_from_zuora

      assert_equal new_bill_cycle_day, customer.read_attribute(:bill_cycle_day)
    end

    test "does not update without a zuora account" do
      customer = create :customer, :zuora, bill_cycle_day: 1

      Billing::Zuora::Account.expects(:find).returns(nil)

      assert_no_changes -> { customer.reload.read_attribute(:bill_cycle_day) } do
        customer.update_from_zuora
      end
    end
  end if GitHub.billing_enabled?

  context "#update_payment_method_details" do
    test "on success" do
      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        user = create(:user)

        zuora_successful_customer_account_creation(user)
        user.reload

        customer = user.customer
        result = customer.update_payment_method_details zuora_parsed_payment_details.merge(
          zuora_payment_method_id: zuora_new_payment_method_id,
          vat_code: "ATU12345678",
          billing_address: {
            country_code_alpha3: "USA",
            region: "Montana",
            postal_code: "91210",
          },
        )

        assert result.success?
        assert_nil customer.billing_extra
        assert_equal "ATU12345678", customer.vat_code
        assert_equal "US",          customer.country_code_alpha2
        assert_equal "Montana",     customer.region
        assert_equal "91210",       customer.postal_code
        assert_equal "Montana",     customer.payment_method.region
        refute customer.changed?
      end
    end

    test "suspends user when adding a blacklisted payment method from Stripe" do
      user = create(:user, :zuora)
      zuora_successful_customer_account_creation(user)
      user.reload

      refute user.suspended?
      with_live_zuora("zuora/payment_processors/successful_braintree_to_stripe_credit_card_update_payment_details") do
        # Unique number identifier was received from Stripe and
        # recorded in the VCR tape
        stripe_payment_method_id = "2c92c0f87801c54601780bf94dbe5951"
        payment_method_unique_number_identifier = "iHjsZvbXpXJynJ1c"
        create(:blacklisted_payment_method, :suspended, unique_number_identifier: payment_method_unique_number_identifier)

        customer = user.customer
        customer.update_payment_method_details({
          zuora_payment_method_id: stripe_payment_method_id,
          billing_address: {
            country_code_alpha3: "USA",
            region: "Florida",
            postal_code: "33018",
          },
          vat_code: "",
        })

        user.reload

        assert user.suspended?
        assert BlacklistedPaymentMethod.find_by(user_id: user.id).present?
      end
    end

    test "disable user's billing when adding a blacklisted payment method" do
      user = create(:user, :zuora)
      zuora_successful_customer_account_creation(user)
      user.reload

      refute user.suspended?
      with_live_zuora("zuora/payment_processors/successful_braintree_to_stripe_credit_card_update_payment_details") do
        # Unique number identifier was received from Stripe and
        # recorded in the VCR tape
        stripe_payment_method_id = "2c92c0f87801c54601780bf94dbe5951"
        payment_method_unique_number_identifier = "iHjsZvbXpXJynJ1c"
        create(:blacklisted_payment_method, :billing_locked, unique_number_identifier: payment_method_unique_number_identifier)

        customer = user.customer
        customer.update_payment_method_details({
          zuora_payment_method_id: stripe_payment_method_id,
          billing_address: {
            country_code_alpha3: "USA",
            region: "Florida",
            postal_code: "33018",
          },
          vat_code: "",
        })

        user.reload

        refute user.suspended?
        assert user.disabled?
        assert BlacklistedPaymentMethod.find_by(user_id: user.id).present?
      end
    end

    test "publishes abuse classification hydro event" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        user = create(:user, :zuora)
        zuora_successful_customer_account_creation(user)
        user.reload

        with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
          # Unique number identifier was received from Braintree and
          # recorded in the VCR tape zuora_successful_customer_account_creation
          payment_method_unique_number_identifier = "753546e62855075ee4522b4137b83f02"
          create(:blacklisted_payment_method, unique_number_identifier: payment_method_unique_number_identifier)

          customer = user.customer
          with_live_zuora("zuora_subscription/successful_create_account_with_card_blacklisted") do
            customer.update_payment_method_details(zuora_parsed_payment_details)
          end

          message = {
            request_context: nil,
            actor: nil,
            account: Hydro::EntitySerializer.user(user.reload),
            previous_classification: :NONE,
            current_classification: :NONE,
            previous_spammy_reason: { value: "" },
            current_spammy_reason: { value: "" },
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
    end
  end if GitHub.billing_enabled?

  context "#async_pending_cycle_change" do
    test "mimics behavior of pending_cycle_change" do
      plan_subscription = create :billing_plan_subscription, :business_owned
      business = plan_subscription.billable_entity
      customer = business.customer
      create :billing_pending_plan_change, :business, customer: customer

      assert_equal customer.pending_cycle_change, customer.async_pending_cycle_change.sync
    end
  end if GitHub.billing_enabled?

  context "#update_from_account_screening_record" do
    test "updates zuora data" do
      GitHub.flipper[:read_billing_information_from_contacts].disable
      trade_screening_record = create(:account_screening_profile, :with_populated_attributes, :with_business)
      business = trade_screening_record.business
      zuora_successful_customer_account_creation(business)
      business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
      with_live_zuora("zuora/update_customer_business_billing_address") do
        zuora_successful_customer_account_creation(business)
        customer = business.reload.customer
        assert customer.payment_method.present?
        perform_enqueued_jobs(only: Billing::SynchronizeCustomerPaymentContactJob) do
          assert customer.update_from_account_screening_record(trade_screening_record)
          assert_equal customer.name, trade_screening_record.fullname
          assert_equal customer.street_address, trade_screening_record.address1
          assert_equal customer.postal_code, trade_screening_record.postal_code
          assert_equal customer.country_code_alpha2, trade_screening_record.country_code
          assert_equal customer.region, trade_screening_record.region
          assert_equal customer.vat_code, trade_screening_record.vat_code
        end
      end
    end
  end if GitHub.billing_enabled?

  context "#update_contact_information" do
    test "updates zuora data for trade screening record" do
      GitHub.flipper[:read_billing_information_from_contacts].disable
      trade_screening_record = create(:account_screening_profile, :with_business, :with_populated_attributes)
      owner = trade_screening_record.owner
      zuora_successful_customer_account_creation(owner)
      customer = owner.reload.customer

      assert customer.update_contact_information(trade_screening_record)

      assert_equal customer.name, trade_screening_record.fullname
      assert_equal customer.street_address, trade_screening_record.address1
      assert_equal customer.postal_code, trade_screening_record.postal_code
      assert_equal customer.country_code_alpha2, trade_screening_record.country_code
      assert_equal customer.region, trade_screening_record.region
      assert_equal customer.vat_code, trade_screening_record.vat_code
    end

    test "updates zuora data for billing contact" do
      GitHub.flipper[:read_billing_information_from_contacts].enable
      trade_screening_record = create(:account_screening_profile, :with_business, :with_populated_attributes, skip_contact_creation: true)
      owner = trade_screening_record.owner
      zuora_successful_customer_account_creation(owner)
      customer = owner.reload.customer
      contact = create(:billing_contact, :with_business, customer: customer)

      assert customer.update_contact_information(contact)

      assert_equal customer.name, contact.fullname
      assert_equal customer.street_address, contact.address1
      assert_equal customer.postal_code, contact.postal_code
      assert_equal customer.country_code_alpha2, contact.country_code
      assert_equal customer.region, contact.region
      assert_equal customer.vat_code, trade_screening_record.vat_code
    end

    test "only updates zuora billing data from contact if flag is enabled" do
      GitHub.flipper[:read_billing_information_from_contacts].enable
      trade_screening_record = create(:account_screening_profile, :with_business, :with_populated_attributes)
      owner = trade_screening_record.owner
      zuora_successful_customer_account_creation(owner)
      customer = owner.reload.customer
      contact = owner.billing_contact
      customer.update!(vat_code: "1234")

      assert customer.reload.update_contact_information(contact)

      assert_equal customer.name, contact.fullname
      assert_equal customer.street_address, contact.address1
      assert_equal customer.postal_code, contact.postal_code
      assert_equal customer.country_code_alpha2, contact.country_code
      assert_equal customer.region, contact.region
      assert_equal customer.vat_code, "1234"

      assert customer.reload.update_contact_information(trade_screening_record)

      assert_equal customer.name, contact.fullname
      assert_equal customer.street_address, contact.address1
      assert_equal customer.postal_code, contact.postal_code
      assert_equal customer.country_code_alpha2, contact.country_code
      assert_equal customer.region, contact.region
      assert_equal customer.vat_code, trade_screening_record.vat_code
    end

    test "returns false for shipping contact" do
      user = create(:credit_card_user)
      customer = user.customer
      contact = create(:shipping_contact, customer: customer)

      refute customer.update_contact_information(contact)
    end
  end if GitHub.billing_enabled?

  context "#update_external_account_name" do
    test "updates zuora name if customer is a user" do
      with_live_zuora("zuora/update_customer_account_name") do
        user = create :user
        zuora_successful_customer_account_creation(user)
        customer = user.reload.customer

        before_update_account = customer.zuora_account
        refute_equal user.login, before_update_account["basicInfo"]["name"]
        refute_equal user.login, before_update_account["billToContact"]["firstName"]
        refute_equal user.login, before_update_account["billToContact"]["lastName"]
        refute_equal user.login, before_update_account["soldToContact"]["firstName"]
        refute_equal user.login, before_update_account["soldToContact"]["lastName"]

        user.update_column(:login, "updated-name")
        user.update_column(:display_login, "updated-name")
        customer.update_external_account_name

        after_update_account = customer.zuora_account
        assert_equal user.login, after_update_account["basicInfo"]["name"]
        assert_equal user.login, after_update_account["billToContact"]["firstName"]
        assert_equal user.login, after_update_account["billToContact"]["lastName"]
        assert_equal user.login, after_update_account["soldToContact"]["firstName"]
        assert_equal user.login, after_update_account["soldToContact"]["lastName"]
      end
    end

    test "updates zuora name if customer is a Business" do
      with_live_zuora("zuora/update_customer_account_name_business_name") do
        business = create :business
        zuora_successful_customer_account_creation(business)
        customer = business.reload.customer

        before_update_account = customer.zuora_account
        refute_equal business.name, before_update_account["basicInfo"]["name"]
        refute_equal business.name, before_update_account["billToContact"]["firstName"]
        refute_equal business.name, before_update_account["billToContact"]["lastName"]
        refute_equal business.name, before_update_account["soldToContact"]["firstName"]
        refute_equal business.name, before_update_account["soldToContact"]["lastName"]

        business.update_column(:name, "new-name")
        customer.update_external_account_name

        after_update_account = customer.zuora_account
        assert_equal business.name, after_update_account["basicInfo"]["name"]
        assert_equal business.name, after_update_account["billToContact"]["firstName"]
        assert_equal business.name, after_update_account["billToContact"]["lastName"]
        assert_equal business.name, after_update_account["soldToContact"]["firstName"]
        assert_equal business.name, after_update_account["soldToContact"]["lastName"]
      end
    end
  end if GitHub.billing_enabled?

  context "#cancel_external_subscriptions" do
    test "queues jobs to cancel multiple external subscriptions" do
      general_plan_sub = create(:billing_plan_subscription, :zuora)
      customer = general_plan_sub.customer
      create(:billing_plan_subscription, :zuora, customer: customer, purpose: :sponsors)
      plan_subscriptions = customer.plan_subscriptions

      assert_equal 2, plan_subscriptions.count

      assert_enqueued_jobs(2, only: CloseOutZuoraSubscriptionJob) do
        customer.cancel_external_subscriptions
      end
      plan_subscriptions.each do |plan_sub|
        assert_enqueued_with(job: CloseOutZuoraSubscriptionJob,
          args: [{
            zuora_subscription_number: plan_sub.zuora_subscription_number,
            plan_subscription: plan_sub,
          }]
        )
      end
    end

    test "only queues cancellation of external subscriptions" do
      general_plan_sub = create(:billing_plan_subscription)
      customer = general_plan_sub.customer
      sponsors_plan_sub = create(:billing_plan_subscription, :zuora, customer: customer, purpose: :sponsors)
      plan_subscriptions = customer.plan_subscriptions

      assert_equal 2, plan_subscriptions.count
      refute_predicate general_plan_sub, :has_external_subscription?

      assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
        customer.cancel_external_subscriptions
      end
      assert_enqueued_with(job: CloseOutZuoraSubscriptionJob,
        args: [{
          zuora_subscription_number: sponsors_plan_sub.zuora_subscription_number,
          plan_subscription: sponsors_plan_sub,
        }]
      )
    end
  end if GitHub.billing_enabled?

  context "#zuora_account" do
    test "can retreive a Zuora account object" do
      with_live_zuora("zuora/get_account_by_id") do
        zuora_account_id = "2c92c0f85cee08f6015d153382da58b4"
        customer = create(:customer, zuora_account_id: zuora_account_id)

        zuora_account = customer.zuora_account

        assert_equal zuora_account_id, zuora_account.id
      end
    end
  end if GitHub.billing_enabled?

  context "#bill_cycle_day" do
    test "returns the bill cycle day stored in the column" do
      customer = create(:customer, bill_cycle_day: 10)

      assert_equal 10, customer.bill_cycle_day
    end
  end if GitHub.billing_enabled?

  context "#credit_balance", skip_enterprise: true do
    test "returns the credit balance from the Zuora accout" do
      with_live_zuora("zuora/object/get_account") do
        zuora_account_id = "2c92c0f85cee08f6015d153382da58b4"
        customer = create(:customer, zuora_account_id: zuora_account_id)

        assert_equal Billing::Money.new(0), customer.credit_balance
      end
    end

    test "returns nil when the Zuora account is not found" do
      with_live_zuora("zuora/get_account_not_found") do
        zuora_account_id = "2c92c0f85cee08f6015d153382da58b5"
        customer = create(:customer, zuora_account_id: zuora_account_id)

        assert_nil customer.credit_balance
      end
    end
  end

  context "#sufficient_balance?", skip_enterprise: true do
    test "returns true when the credit balance is greater than or equal to the payment amount" do
      with_live_zuora("zuora/object/get_account") do
        zuora_account_id = "2c92c0f85cee08f6015d153382da58b4"
        customer = build(:customer, zuora_account_id: zuora_account_id)
        payment_amount = Billing::Money.new(0)

        sufficient_balance = customer.sufficient_balance?(payment_amount)

        assert sufficient_balance, "expected Zuora account #{zuora_account_id} to have at least #{payment_amount.format}"
      end
    end

    test "returns false when the credit balance is less than the payment amount" do
      with_live_zuora("zuora/object/get_account") do
        zuora_account_id = "2c92c0f85cee08f6015d153382da58b4"
        customer = build(:customer, zuora_account_id: zuora_account_id)
        payment_amount = Billing::Money.new(100)

        sufficient_balance = customer.sufficient_balance?(payment_amount)

        refute sufficient_balance, "expected Zuora account #{zuora_account_id} to have at least #{payment_amount.format}"
      end
    end
  end

  context "#azure_subscription_id=", skip_enterprise: true do
    test "allows two records with blank azure subscription IDs" do
      create(:customer, azure_subscription_id: "")

      assert_nothing_raised do
        create(:customer, azure_subscription_id: "")
      end
    end

    test "ensures that it's in the correct format" do
      customer = Customer.new(azure_subscription_id: "not a UUID")
      customer.valid?

      assert customer.errors.details[:azure_subscription_id].present?

      customer.azure_subscription_id = "00000000-0000-0000-0000-000000000000"
      customer.valid?

      refute customer.errors.details[:azure_subscription_id].present?
    end
  end

  context "#destroy" do
    test "cleans up plan subscriptions on destroy" do
      customer = create :customer
      create :billing_plan_subscription, customer: customer

      assert_difference "Billing::PlanSubscription.count", -1 do
        customer.destroy
      end
    end
  end

  context "#invoiced?" do
    test "returns true if billing_type is invoice" do
      @customer.update_attribute(:billing_type, "invoice")

      assert_equal "invoice", @customer.billing_type
      assert_predicate @customer, :invoiced?
    end

    test "returns false if billing_type is card" do
      @customer.update_attribute(:billing_type, "card")

      assert_equal "card", @customer.billing_type
      refute_predicate @customer, :invoiced?
    end

    test "returns false if billing_type is not set" do
      assert_nil @customer.billing_type
      refute_predicate @customer, :invoiced?
    end
  end

  context "#self_serve_payment?" do
    test "returns true if billing_type is card" do
      @customer.update_attribute(:billing_type, "card")

      assert_equal "card", @customer.billing_type
      assert_predicate @customer, :self_serve_payment?
    end

    test "returns false if billing_type is invoice" do
      @customer.update_attribute(:billing_type, "invoice")

      assert_equal "invoice", @customer.billing_type
      refute_predicate @customer, :self_serve_payment?
    end

    test "returns false if billing_type is not set" do
      assert_nil @customer.billing_type
      refute_predicate @customer, :self_serve_payment?
    end
  end

  context "#billable_owner" do
    test "returns business for billable owner if the customer has a business" do
      customer = create(:customer, :zuora)
      business = create(:business, customer: customer)
      assert_equal customer.billable_owner, business
    end

    test "returns business for billable owner if the customer has a business and a user" do
      customer = create(:customer, :zuora)
      business = create(:business, customer: customer)
      user = create(:user)
      create(:customer_account, user: user, customer: customer)
      assert_equal customer.billable_owner, business
    end

    test "returns business for billable owner if the customer has a business and an org" do
      customer = create(:customer, :zuora)
      business = create(:business, customer: customer)
      organization = create(:organization)
      create(:customer_account, user: organization, customer: customer)
      assert_equal customer.billable_owner, business
    end

    test "returns org for billable owner if the customer has one org" do
      customer = create(:customer, :zuora)
      organization = create(:organization)
      create(:customer_account, user: organization, customer: customer)
      customer.reload

      assert_equal customer.billable_owner, organization
    end

    test "returns user for billable owner if the customer has one user" do
      customer = create(:customer, :zuora)
      user = create(:user)
      create(:customer_account, user: user, customer: customer)
      customer.reload

      assert_equal customer.billable_owner, user
    end

    test "returns nil for billable owner if the customer has multiple orgs" do
      customer = create(:customer, :zuora)
      organization = create(:organization)
      create(:customer_account, user: organization, customer: customer)
      organization = create(:organization)
      create(:customer_account, user: organization, customer: customer)
      assert_nil customer.billable_owner
    end

    test "returns nil for the billable owner if the customer has multiple users" do
      customer = create(:customer, :zuora)
      user = create(:user)
      create(:customer_account, user: user, customer: customer)
      user = create(:user)
      create(:customer_account, user: user, customer: customer)
      assert_nil customer.billable_owner
    end

    test "returns nil for the billable owner if the customer has no users/orgs or a business" do
      customer = create(:customer, :zuora)
      assert_nil customer.billable_owner
    end
  end

  context "metered_via_azure override", skip_enterprise: true do
    test "update with azure subscription does not disable metered_via_azure" do
      azure_subscription_id = SecureRandom.uuid
      customer = Customer.new
      customer.name = "Acme, Incustomer."
      customer.azure_subscription_id = nil
      customer.metered_via_azure = true
      customer.save

      assert customer.metered_via_azure

      customer.update(azure_subscription_id: azure_subscription_id)

      assert_equal azure_subscription_id, customer.reload.azure_subscription_id
      assert customer.reload.metered_via_azure
    end

    test "update without azure subscription disables metered_via_azure" do
      customer = Customer.new
      customer.name = "Acme, Incustomer."
      customer.azure_subscription_id = SecureRandom.uuid
      customer.metered_via_azure = true
      customer.save

      assert customer.metered_via_azure

      customer.update(azure_subscription_id: nil)

      assert_nil customer.reload.azure_subscription_id
      refute customer.reload.metered_via_azure
    end
  end

  context "#invalid_azure_subscription_detected?", skip_enterprise: true do
    test "returns false if Azure subscription is not present" do
      Timecop.freeze do
        customer = Customer.new
        customer.name = "Acme, Incustomer."
        customer.azure_subscription_id = nil
        customer.save

        Billing::Kv.store.set(customer.invalid_azure_subscription_id_key, "true", expires: 1.day.from_now)

        refute customer.invalid_azure_subscription_detected?
      end
    end

    test "returns false if Azure subscription is present but key is not set" do
      customer = Customer.new
      customer.name = "Acme, Incustomer."
      customer.azure_subscription_id = SecureRandom.uuid
      customer.save

      refute customer.invalid_azure_subscription_detected?
    end

    test "returns true if Azure subscription is present and key is set" do
      Timecop.freeze do
        customer = Customer.new
        customer.name = "Acme, Incustomer."
        customer.azure_subscription_id = SecureRandom.uuid
        customer.save

        Billing::Kv.store.set(customer.invalid_azure_subscription_id_key, "true", expires: 1.day.from_now)

        assert customer.invalid_azure_subscription_detected?
      end
    end
  end

  context "instrumentation", skip_enterprise: true do
    test "does not instrument metered_via_azure when field is not updated" do
      enabled_events = subscribe @metered_via_azure_enabled_event
      disabled_events = subscribe @metered_via_azure_disabled_event

      customer = create(:customer)
      customer.azure_subscription_id = "00000000-0000-0000-0000-000000000000"
      customer.save!

      assert enabled_events.empty?
      assert disabled_events.empty?
      assert_dogstats_increment(0, @metered_via_azure_stats_name)
    end

    test "instruments metered_via_azure when field is updated" do
      enabled_events = subscribe @metered_via_azure_enabled_event
      disabled_events = subscribe @metered_via_azure_disabled_event

      customer = create(:customer, metered_via_azure: false)

      azure_subscription_id = SecureRandom.uuid

      expected_payload = {
        azure_subscription_id: "#{azure_subscription_id.first(5)}*************************#{azure_subscription_id.last(6)}",
        metered_ghe: customer.metered_ghe,
        billing_type: "none",
        linked_azure_subscription: true,
        billed_via_billing_platform: customer.billed_via_billing_platform,
        metered_via_azure: true,
        customer_id: customer.id,
      }

      customer.metered_via_azure = true
      customer.azure_subscription_id = azure_subscription_id
      customer.save!

      assert disabled_events.empty?
      assert event = enabled_events.pop, "#{@metered_via_azure_enabled_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @metered_via_azure_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:none",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:true",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])

      customer.metered_via_azure = false
      customer.save!

      expected_payload.merge!(metered_via_azure: false)

      assert enabled_events.empty?
      assert event = disabled_events.pop, "#{@metered_via_azure_disabled_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @metered_via_azure_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:none",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:false",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])
    end

    test "does not instrument azure_subscription_id when field is not updated" do
      linked_events = subscribe @azure_subscription_linked_event
      unlinked_events = subscribe @azure_subscription_unlinked_event

      customer = create(:customer, metered_via_azure: false)

      assert linked_events.empty?
      assert unlinked_events.empty?
      assert_dogstats_increment(0, @azure_subscription_stats_name)
    end

    test "instruments azure_subscription_id when field is updated" do
      linked_events = subscribe @azure_subscription_linked_event
      unlinked_events = subscribe @azure_subscription_unlinked_event

      customer = create(:customer)

      expected_payload = {
        billing_type: "none",
        customer_id: customer.id,
        metered_ghe: customer.metered_ghe,
        metered_via_azure: customer.metered_via_azure,
        billed_via_billing_platform: customer.billed_via_billing_platform,
      }

      customer.azure_subscription_id = "00000000-0000-0000-0000-000000000000"
      customer.save!

      expected_payload.merge!(
        linked_azure_subscription: true,
        azure_subscription_id: "00000*************************000000"
      )

      assert unlinked_events.empty?
      assert event = linked_events.pop, "#{@azure_subscription_linked_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @azure_subscription_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:none",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:#{customer.metered_via_azure}",
        "linked_azure_subscription:true",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])

      customer.azure_subscription_id = nil
      customer.save!

      expected_payload.merge!(linked_azure_subscription: false)

      assert linked_events.empty?
      assert event = unlinked_events.pop, "#{@azure_subscription_unlinked_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @azure_subscription_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:none",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:#{customer.metered_via_azure}",
        "linked_azure_subscription:false",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])
    end

    test "does not instrument billed_via_billing_platform when field is not updated" do
      enabled_events = subscribe @billing_platform_emission_enabled_event
      disabled_events = subscribe @billing_platform_emission_disabled_event

      customer = create(:customer)
      customer.azure_subscription_id = "00000000-0000-0000-0000-000000000000"
      customer.save!

      assert enabled_events.empty?
      assert disabled_events.empty?
      assert_dogstats_increment(0, @billed_via_billing_platform_stats_name)
    end

    test "instruments billed_via_billing_platform when field is updated" do
      enabled_events = subscribe @billing_platform_emission_enabled_event
      disabled_events = subscribe @billing_platform_emission_disabled_event

      customer = create(:customer, billed_via_billing_platform: false)

      expected_payload = {
        customer_id: customer.id,
        linked_azure_subscription: customer.azure_subscription_id.present?,
        metered_ghe: customer.metered_ghe,
        billing_type: "none",
        metered_via_azure: customer.metered_via_azure,
        billed_via_billing_platform: customer.billed_via_billing_platform,
      }

      customer.billed_via_billing_platform = true
      customer.save!

      expected_payload.merge!(billed_via_billing_platform: true)

      assert disabled_events.empty?
      assert event = enabled_events.pop, "#{@billing_platform_emission_enabled_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @billed_via_billing_platform_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:none",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:#{customer.metered_via_azure}",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])

      customer.billed_via_billing_platform = false
      customer.save!

      expected_payload.merge!(billed_via_billing_platform: false)

      assert enabled_events.empty?
      assert event = disabled_events.pop, "#{@billing_platform_emission_disabled_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @billed_via_billing_platform_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:none",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:#{customer.metered_via_azure}",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])
    end

    test "instruments billing type" do
      enabled_events = subscribe @metered_via_azure_enabled_event

      customer = create(:customer, metered_via_azure: false, billing_type: "card")

      azure_subscription_id = SecureRandom.uuid

      expected_payload = {
        azure_subscription_id: "#{azure_subscription_id.first(5)}*************************#{azure_subscription_id.last(6)}",
        customer_id: customer.id,
        linked_azure_subscription: true,
        metered_ghe: customer.metered_ghe,
        billing_type: "card",
        billed_via_billing_platform: customer.billed_via_billing_platform,
      }

      customer.metered_via_azure = true
      customer.azure_subscription_id = azure_subscription_id
      customer.save!

      expected_payload.merge!(metered_via_azure: true)

      assert event = enabled_events.pop, "#{@metered_via_azure_enabled_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @metered_via_azure_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:card",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:true",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])
    end

    test "instruments masked azure subscription id" do
      enabled_events = subscribe @metered_via_azure_enabled_event
      azure_subscription_id = SecureRandom.uuid

      customer = create(:customer, metered_via_azure: false, billing_type: "card", azure_subscription_id: azure_subscription_id)

      expected_payload = {
        azure_subscription_id: "#{azure_subscription_id.first(5)}*************************#{azure_subscription_id.last(6)}",
        billing_type: "card",
        customer_id: customer.id,
        linked_azure_subscription: customer.azure_subscription_id.present?,
        metered_ghe: customer.metered_ghe,
        billed_via_billing_platform: customer.billed_via_billing_platform,
      }

      customer.metered_via_azure = true
      customer.save!

      expected_payload.merge!(metered_via_azure: true)

      assert event = enabled_events.pop, "#{@metered_via_azure_enabled_event} event was expected"
      assert_equal expected_payload, event.payload

      assert_dogstats_increment(1, @metered_via_azure_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:card",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:true",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])
    end

    test "instruments zuora account information" do
      enabled_events = subscribe @metered_via_azure_enabled_event

      customer = create(:credit_card_customer, metered_via_azure: false, billing_type: "card")

      azure_subscription_id = SecureRandom.uuid

      expected_payload = {
        azure_subscription_id: "#{azure_subscription_id.first(5)}*************************#{azure_subscription_id.last(6)}",
        billing_type: "card",
        customer_id: customer.id,
        linked_azure_subscription: true,
        metered_ghe: customer.metered_ghe,
        zuora_account_id: customer.zuora_account_id,
        zuora_account_number: customer.zuora_account_number,
        billed_via_billing_platform: customer.billed_via_billing_platform,
      }

      customer.metered_via_azure = true
      customer.azure_subscription_id = azure_subscription_id
      customer.save!

      expected_payload.merge!(metered_via_azure: true)

      assert event = enabled_events.pop, "#{@metered_via_azure_enabled_event} event was expected"
      assert_equal expected_payload, event.payload
      refute_nil event.payload[:zuora_account_id]
      refute_nil event.payload[:zuora_account_number]

      assert_dogstats_increment(1, @metered_via_azure_stats_name, tags: [
        "billable_owner_type:#{customer.billable_owner.class.name}",
        "billing_type:card",
        "metered_ghe:#{customer.metered_ghe}",
        "metered_via_azure:true",
        "linked_azure_subscription:#{customer.azure_subscription_id.present?}",
        "billed_via_billing_platform:#{customer.billed_via_billing_platform}",
      ])
    end
  end

  context "billing-platform customer updates and creates" do
    test "job is queued when a customer is created" do
      #One creation, one job
      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        customer = create(:credit_card_customer, metered_ghe: false, metered_via_azure: false, billing_type: "card")
        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [customer])
      end

      #One creation, one dogstat
      assert_dogstats_increment(1, "billing_customer.billing_platform_update_customer")
      assert_dogstats_increment(1, "billing_customer.billing_platform_update_customer_called")
    end

    test "job is queued when updating billed_via_billing_platform" do
      customer = create(:credit_card_customer, metered_ghe: false, metered_via_azure: false, billing_type: "card")
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      #One update, one job
      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        customer.billed_via_billing_platform = true
        customer.save!

        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [customer])
      end

      #One on creation and one on update
      assert_dogstats_increment(2, "billing_customer.billing_platform_update_customer")
      assert_dogstats_increment(2, "billing_customer.billing_platform_update_customer_called")
    end

    test "job is queued during touch" do
      customer = create(:credit_card_customer, metered_ghe: false, metered_via_azure: false, billing_type: "card")
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      # One touch, one job
      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        customer.touch
        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [customer])
      end

      #One on creation and one on touch
      assert_dogstats_increment(2, "billing_customer.billing_platform_update_customer")
      assert_dogstats_increment(2, "billing_customer.billing_platform_update_customer_called")
    end
  end unless GitHub.enterprise?

  context "#git_lfs_enabled?" do
    test "when enabled" do
      create :billing_platform_enabled_product, git_lfs: true, customer_id: @customer.id

      assert @customer.billing_platform_enabled_product.git_lfs?
    end

    test "when disabled" do
      create :billing_platform_enabled_product, git_lfs: false, customer_id: @customer.id

      refute @customer.billing_platform_enabled_product.git_lfs?
    end
  end

  context "#products_billed_via_billing_platform" do
    test "pulls values from billing_platform_enabled_products table" do
      create :billing_platform_enabled_product, actions: true, codespaces: true, git_lfs: false, customer_id: @customer.id

      assert_same_elements @customer.products_billed_via_billing_platform, %w[codespaces actions]
    end

    test "creates a new bp enabled product record and returns empty array if a bp enabled product record doesn't exist" do

      assert_nil @customer.billing_platform_enabled_product
      assert_equal @customer.products_billed_via_billing_platform, []
      refute_nil @customer.billing_platform_enabled_product
    end

    test "returns an empty array for a deleted customer" do
      @customer.destroy

      assert_equal @customer.products_billed_via_billing_platform, []
    end
  end

  context "#products_billed_via_billing_platform_friendly_names" do
    test "pulls values from billing_platform_enabled_products table" do
      create :billing_platform_enabled_product, actions: true, codespaces: true, git_lfs: false, customer_id: @customer.id

      assert_same_elements @customer.products_billed_via_billing_platform_friendly_names, %w[Codespaces Actions]
    end

    test "returns the friendly names for ghec, git_lfs, and ghas" do
      create :billing_platform_enabled_product, git_lfs: true, ghas: true, ghec: true, actions: false, codespaces: false, customer_id: @customer.id

      assert_same_elements @customer.products_billed_via_billing_platform_friendly_names, ["Git LFS", "Advanced Security", "GitHub Enterprise"]
    end

    test "creates a new bp enabled product record and returns empty array if a bp enabled product record doesn't exist" do

      assert_nil @customer.billing_platform_enabled_product
      assert_equal @customer.products_billed_via_billing_platform_friendly_names, []
      refute_nil @customer.billing_platform_enabled_product
    end

    test "returns an empty array for a deleted customer" do
      @customer.destroy

      assert_equal @customer.products_billed_via_billing_platform_friendly_names, []
    end
  end

  context "copilot_billed_on_billing_platform?" do
    test "returns false when BILLING_PLATFORM_COPILOT_ROLLOUT_DATE is in the future" do
      Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.tomorrow) do
        refute @customer.copilot_billed_on_billing_platform?
      end
    end

    test "returns false when BillingPlatformEnabledProduct is not present" do
      Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
        @customer.billing_platform_enabled_product&.destroy
        refute @customer.copilot_billed_on_billing_platform?
      end
    end

    test "returns false when BillingPlatformEnabledProduct#copilot is false" do
      Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
        @customer.billing_platform_enabled_product&.destroy
        create :billing_platform_enabled_product, customer: @customer, copilot: false
        refute @customer.copilot_billed_on_billing_platform?
      end
    end

    test "returns false when BillingPlatformEnabledProduct#copilot is true" do
      Customer.stub_const(:BILLING_PLATFORM_COPILOT_ROLLOUT_DATE, Date.yesterday) do
        @customer.billing_platform_enabled_product&.destroy
        create :billing_platform_enabled_product, customer: @customer, copilot: true
        assert @customer.copilot_billed_on_billing_platform?
      end
    end
  end

  context "#valid_zuora_with_payment" do
    test "returns true when zuora account, subscription, and payment method are present" do
      customer = create(:customer, :zuora)
      create(:billing_plan_subscription, :zuora, customer: customer)

      assert customer.valid_zuora_with_payment?
    end

    test "returns true when zuora account, subscription are present and customer is invoiced" do
      customer = create(:customer, :invoiced,
        zuora_account_id: SecureRandom.hex(16),
        zuora_account_number: SecureRandom.hex(12)
      )
      create(:billing_sales_serve_plan_subscription, customer: customer)

      assert customer.valid_zuora_with_payment?
    end

    test "returns false when zuora account is missing" do
      customer = create(:customer, zuora_account_id: nil)

      refute customer.valid_zuora_with_payment?
    end

    test "returns false when zuora subscription is missing" do
      customer = create(:customer, :zuora)
      customer.update(plan_subscription: nil)

      refute customer.valid_zuora_with_payment?
    end

    test "returns false when zuora payment method is missing" do
      customer = create(:customer, :zuora)
      create(:billing_plan_subscription, :zuora, customer: customer)
      customer.update(payment_method: nil)

      refute customer.valid_zuora_with_payment?
    end
  end

  context "#onboard_to_billing_platform" do
    test "queues onboard job and updates billed_via_billing_platform to true" do
      customer = create(:customer)
      assert_enqueued_jobs(1, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
        customer.onboard_to_billing_platform(products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize])
        assert customer.billed_via_billing_platform
      end
    end
  end if GitHub.billing_enabled?

  context "#has_auto_pay_enabled?" do
    test "returns true for a customer with no auto pay disabled reasons" do
      customer = create(:customer, :zuora)
      customer.update auto_pay_reasons: Set[]

      assert customer.has_auto_pay_enabled?
    end

    test "returns false for a customer with auto pay disabled reasons" do
      customer = create(:customer, :zuora)
      customer.update auto_pay_reasons: Set[:india_rbi]

      refute customer.has_auto_pay_enabled?
    end
  end

  context "#is_enterprise_vnext_native?" do
    test "returns true if the business customer is billing vnext enabled and signed up after the GA date" do
      customer = create(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day
      assert customer.is_vnext_native?
    end

    test "returns false if the customer is billing vnext enabled and signed up after the GA date but no business is linked to the customer" do
      customer = create(:customer, business: nil, billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day
      refute customer.is_vnext_native?
    end

    test "returns false if the business customer is created after the GA date but migrated to vnext 2 days later" do
      customer = create(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 3.days
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is billing vnext enabled and signed before the GA date" do
      customer = create(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is not billing vnext enabled and signed after after the GA date" do
      customer = build(:customer, business: build(:business), billed_via_billing_platform: false, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is not billing vnext enabled and signed before the GA date" do
      customer = build(:customer, billed_via_billing_platform: false, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      refute customer.is_vnext_native?
    end
  end

  context "#is_vnext_native?" do
    test "returns true if the customer is business customer and billing vnext enabled and signed up after the GA date" do
      customer = create(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day
      assert customer.is_vnext_native?
    end

    test "returns true if the customer is organization customer and billing vnext enabled and signed up after the GA date" do
      organization = create(:organization)
      customer = create(:customer, billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create(:customer_account, user: organization, customer: customer)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day
      assert customer.is_vnext_native?
    end

    test "returns true if the customer is user customer and billing vnext enabled and signed up after the GA date" do
      user = create(:user)
      customer = create(:customer, billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create(:customer_account, user: user, customer: customer)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day
      assert customer.is_vnext_native?
    end

    test "returns false if the customer is generic customer and billing vnext enabled and signed up after the GA date" do
      customer = create(:customer, billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is created after the GA date but migrated to vnext 2 days later" do
      customer = create(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 3.days
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is billing vnext enabled and signed before the GA date" do
      customer = create(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      create :billing_platform_enabled_product, customer: customer, migration_date: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is not billing vnext enabled and signed after after the GA date" do
      customer = build(:customer, business: build(:business), billed_via_billing_platform: false, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      refute customer.is_vnext_native?
    end

    test "returns false if the customer is not billing vnext enabled and signed before the GA date" do
      customer = build(:customer, billed_via_billing_platform: false, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      refute customer.is_vnext_native?
    end
  end

  context "#is_enterprise_vnext_beta?" do
    test "returns true if the business customer is billing vnext enabled and signed up before the GA date" do
      customer = build(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      assert customer.is_enterprise_vnext_beta?
    end

    test "returns false if the customer is billing vnext enabled and signed up before the GA date but no business is linked to the customer" do
      customer = build(:customer, business: nil, billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      refute customer.is_enterprise_vnext_beta?
    end

    test "returns false if the customer is billing vnext enabled and signed after the GA date" do
      customer = build(:customer, business: build(:business), billed_via_billing_platform: true, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      refute customer.is_enterprise_vnext_beta?
    end

    test "returns false if the customer is not billing vnext enabled and signed before the GA date" do
      customer = build(:customer, business: build(:business), billed_via_billing_platform: false, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      refute customer.is_enterprise_vnext_beta?
    end

    test "returns false if the customer is not billing vnext enabled and signed after the GA date" do
      customer = build(:customer, billed_via_billing_platform: false, created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE + 1.day)
      refute customer.is_enterprise_vnext_beta?
    end
  end

  context "#migration_happened_in_last_thirty_days?" do
    test "returns true if the migration happened in the last 30 days" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: 15.days.ago,
        customer: customer
      )

      assert customer.migration_happened_in_last_thirty_days?
    end

    test "returns true if the migration happened exactly 30 days ago" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: 30.days.ago,
        customer: customer
      )

      assert customer.migration_happened_in_last_thirty_days?
    end

    test "returns false if the migration happened in the last 45 days" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: 45.days.ago,
        customer: customer
      )

      refute customer.migration_happened_in_last_thirty_days?
    end

    test "returns false if the migration hasn't happened and is in the future" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: DateTime.now + 3.days,
        customer: customer
      )

      refute customer.migration_happened_in_last_thirty_days?
    end

    test "returns true on the first day of migration" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: DateTime.now,
        customer: customer
      )

      assert customer.migration_happened_in_last_thirty_days?
    end
  end

  context "#migration_happened_more_than_thirty_days_ago?" do
    test "returns false if the migration happened in the last 30 days" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: 15.days.ago,
        customer: customer
      )

      refute customer.migration_happened_more_than_thirty_days_ago?
    end

    test "returns true if the migration happened more than 30 days ago" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: 45.days.ago,
        customer: customer
      )

      assert customer.migration_happened_more_than_thirty_days_ago?
    end

    test "returns false if the migration hasn't happened and is in the future" do
      customer = create(:customer, business: create(:business))
      create(:billing_platform_enabled_product,
        migration_date: DateTime.now + 3.days,
        customer: customer
      )

      refute customer.migration_happened_more_than_thirty_days_ago?
    end
  end


  context "#requires_azure_subscription?" do
    test "returns true if the customer is metered via azure" do
      customer = build(:customer, metered_via_azure: true)
      assert customer.requires_azure_subscription?
    end

    test "returns false if the customer is not metered via azure" do
      customer = build(:customer, metered_via_azure: false)
      refute customer.requires_azure_subscription?
    end

    test "returns false if the customer is metered but not through azure" do
      customer = build(:customer, metered_via_azure: false, metered_ghe: true)
      refute customer.requires_azure_subscription?
    end

    test "returns true if the customer is metered and through azure" do
      customer = build(:customer, metered_via_azure: true, metered_ghe: true)
      assert customer.requires_azure_subscription?
    end
  end

  context "#in_taxable_country" do
    test "returns true when the customer has a billing address in the United States" do
      user = create(:credit_card_user)
      trade_screening_record = create(:account_screening_profile, owner: user, country_code: "US")

      assert trade_screening_record.country_is_united_states?
      assert user.customer.in_taxable_country?
    end

    test "returns false when the customer has a billing address in Canada" do
      user = create(:credit_card_user)
      trade_screening_record = create(:account_screening_profile, owner: user, country_code: "CA")

      refute trade_screening_record.country_is_united_states?
      refute user.customer.in_taxable_country?
    end

    test "returns true when the customer has a shipping address in the United States" do
      user = create(:credit_card_user)
      contact = create(:billing_contact, :shipping, customer: user.customer, country_code: "US")

      assert user.customer.in_taxable_country?
    end

    test "returns false when the customer has a shipping address in Canada" do
      GitHub.flipper[:billing_use_zuora_sold_to_country].enable
      user = create(:credit_card_user)
      contact = create(:billing_contact, :shipping, customer: user.customer, country_code: "CA")

      refute user.customer.in_taxable_country?
    end

    context "when the customer has no trade screening record or shipping contact" do
      test "returns false when the feature flag is disabled" do
        GitHub.flipper[:billing_use_zuora_sold_to_country].disable
        user = create(:credit_card_user)

        Zuorest::Model::Account.expects(:find).never

        refute user.has_saved_trade_screening_record?
        assert user.shipping_contact.new_record?
        refute user.customer.in_taxable_country?
      end

      test "returns true when the customer has a Zuora sold to contact in the United States" do
        GitHub.flipper[:billing_use_zuora_sold_to_country].enable
        user = create(:credit_card_user)

        fake_zuora_account = Zuorest::Model::Account.new(
          success: true,
          basicInfo: {
            "id" => user.customer.zuora_account_id,
            "accountNumber" => user.customer.zuora_account_number,
            "status" => "Active",
          },
          billingAndPayment: {
            "billCycleDay" => 20,
            "autoPay" => true,
          },
          metrics: {},
          billToContact: {},
          soldToContact: {
            "country" => "United States",
          },
        )
        Zuorest::Model::Account.expects(:find).once.returns(fake_zuora_account)
        GitHub.logger.expects(:info).once

        refute user.has_saved_trade_screening_record?
        assert user.shipping_contact.new_record?
        assert user.customer.in_taxable_country?
        assert_dogstats_increment(1, "customer.zuora_sold_to_country", tags: ["success:true", "country:United States"])
      end

      test "returns false when the customer has a Zuora sold to contact in Canada" do
        GitHub.flipper[:billing_use_zuora_sold_to_country].enable
        user = create(:credit_card_user)

        fake_zuora_account = Zuorest::Model::Account.new(
          success: true,
          basicInfo: {
            "id" => user.customer.zuora_account_id,
            "accountNumber" => user.customer.zuora_account_number,
            "status" => "Active",
          },
          billingAndPayment: {
            "billCycleDay" => 20,
            "autoPay" => true,
          },
          metrics: {},
          billToContact: {},
          soldToContact: {
            "country" => "Canada",
          },
        )
        Zuorest::Model::Account.expects(:find).once.returns(fake_zuora_account)
        GitHub.logger.expects(:info).once

        refute user.has_saved_trade_screening_record?
        assert user.shipping_contact.new_record?
        refute user.customer.in_taxable_country?
        assert_dogstats_increment(1, "customer.zuora_sold_to_country", tags: ["success:true", "country:Canada"])
      end

      test "returns false when an error occurs while attempting to fetch the Zuora sold to country" do
        GitHub.flipper[:billing_use_zuora_sold_to_country].enable
        user = create(:credit_card_user)

        Zuorest::Model::Account.expects(:find).once.raises(Zuorest::HttpError.new("boom", 500))
        GitHub.logger.expects(:error).once

        refute user.has_saved_trade_screening_record?
        assert user.shipping_contact.new_record?
        refute user.customer.in_taxable_country?
        assert_dogstats_increment(1, "customer.zuora_sold_to_country", tags: ["success:false", "error:Zuorest::HttpError"])
      end

      test "Does not make a Zuora API call on subsequent calls" do
        GitHub.flipper[:billing_use_zuora_sold_to_country].enable
        user = create(:credit_card_user)

        fake_zuora_account = Zuorest::Model::Account.new(
          success: true,
          basicInfo: {
            "id" => user.customer.zuora_account_id,
            "accountNumber" => user.customer.zuora_account_number,
            "status" => "Active",
          },
          billingAndPayment: {
            "billCycleDay" => 20,
            "autoPay" => true,
          },
          metrics: {},
          billToContact: {},
          soldToContact: {
            "country" => "United States",
          },
        )
        Zuorest::Model::Account.expects(:find).once.returns(fake_zuora_account)
        GitHub.logger.expects(:info).once

        refute user.has_saved_trade_screening_record?
        assert user.shipping_contact.new_record?

        10.times do
          assert user.customer.in_taxable_country?
        end

        assert_dogstats_increment(10, "customer.zuora_sold_to_country", tags: ["success:true", "country:United States"])
      end
    end
  end

  context "can be used as flipper actor" do
    test "has a flipper_id" do
      expected_id = "Customer:#{@customer.id}"
      assert_equal expected_id, @customer.flipper_id
      assert_equal expected_id, @customer.vexi_id
    end

    test "allows a feature flag to be enabled and disabled for a customer" do
      feature_name = :test_feature
      feature = create(:flipper_feature, name: feature_name)

      refute @customer.feature_enabled?(feature_name)

      @customer.enable_feature(feature_name)
      assert @customer.feature_enabled?(feature_name)

      @customer.disable_feature(feature_name)
      refute @customer.feature_enabled?(feature_name)
    end
  end

  context "is_legacy_report_an_option?" do
    test "returns true for non-vnext native customers who migrated less than 180 days ago" do
      @customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      create(:billing_platform_enabled_product, customer: @customer, migration_date: 30.days.ago)

      assert @customer.is_legacy_report_an_option?
    end

    test "returns false for vnext native customers" do
      customer = create(:customer, billed_via_billing_platform: true, created_at: 30.days.ago)
      create(:billing_platform_enabled_product, customer: customer, migration_date: nil)

      refute customer.is_legacy_report_an_option?
    end


    test "returns false for non vnext native customer who migrated over 180 days ago" do
      Timecop.freeze do
        @customer.update!(created_at: 185.days.ago)
        create(:billing_platform_enabled_product, customer: @customer, migration_date: 181.days.ago)

        refute @customer.is_legacy_report_an_option?
      end
    end

    test "returns false for non-vnext customer who have not migrated" do
      @customer.update!(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      create(:billing_platform_enabled_product, customer: @customer, migration_date: nil)

      refute @customer.is_legacy_report_an_option?
    end
  end
end
