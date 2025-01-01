# typed: true
# frozen_string_literal: true

require "test_helper"

class PaymentMethodTest < GitHub::TestCase
  include GitHub::BillingTest
  include GitHub::BrainTree::TestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @credit_card_user = create :credit_card_user
    @credit_card_business = create(:business, customer: create(:customer, :self_serve))
  end

  context ".with_card_fingerprint" do
    test "it finds the relevant payment_methods" do
      paypal_payment_method = create(:payment_method, paypal_email: "user1@example.com", unique_number_identifier: nil)
      unique_number_identifier_payment_method = create(:payment_method, paypal_email: nil, unique_number_identifier: "1234")

      paypal_payment_methods = PaymentMethod.with_card_fingerprint(paypal_payment_method.paypal_email)
      assert_equal paypal_payment_methods.count, 1
      assert_equal paypal_payment_methods.first, paypal_payment_method

      unique_number_identifier_payment_methods = PaymentMethod.with_card_fingerprint(unique_number_identifier_payment_method.unique_number_identifier)
      assert_equal unique_number_identifier_payment_methods.count, 1
      assert_equal unique_number_identifier_payment_methods.first, unique_number_identifier_payment_method
    end
  end

  context "::send_expiring_credit_card_reminders" do
    test "enqueues a job for expiring credit cards for Users" do
      @credit_card_user.payment_method.update(expiration_month: 8, expiration_year: 2016)

      not_expiring_user = create :credit_card_user
      not_expiring_user.payment_method.update(expiration_month: 9, expiration_year: 2016)

      assert_enqueued_with job: BillingExpiringCardReminderJob, args: [@credit_card_user] do
        travel_to(Date.new(2016, 7, 2)) do
          PaymentMethod.send_expiring_credit_card_reminders
        end
      end
      assert_enqueued_jobs 1, only: BillingExpiringCardReminderJob
    end

    test "enqueues a job for expiring credit cards for Businesses" do
      @credit_card_business.customer.payment_method.update \
        expiration_month: 8,
        expiration_year: 2016

      not_expiring_business = create(:business, customer: create(:customer, :self_serve))
      not_expiring_business.payment_method.update \
        expiration_month: 9,
        expiration_year: 2016

      assert_enqueued_with job: BillingExpiringCardReminderJob, args: [@credit_card_business] do
        travel_to(Date.new(2016, 7, 2)) do
          PaymentMethod.send_expiring_credit_card_reminders
        end
      end
      assert_enqueued_jobs 1, only: BillingExpiringCardReminderJob
    end

    test "does not enqueue a job for credit cards with deleted Users" do
      @credit_card_user.payment_method.update(expiration_month: 8, expiration_year: 2016)
      @credit_card_user.delete

      assert_no_enqueued_jobs only: BillingExpiringCardReminderJob do
        travel_to(Date.new(2016, 7, 2)) do
          PaymentMethod.send_expiring_credit_card_reminders
        end
      end
    end

    test "does not enqueue a job for credit cards with deleted Businesses" do
      @credit_card_business.customer.payment_method.update \
        expiration_month: 8,
        expiration_year: 2016
      @credit_card_business.destroy

      assert_no_enqueued_jobs only: BillingExpiringCardReminderJob do
        travel_to(Date.new(2016, 7, 2)) do
          PaymentMethod.send_expiring_credit_card_reminders
        end
      end
    end
  end

  context "with_card_fingerprint_reuse_over_threshold_in_last_30_days scope" do
    test "excludes payment methods with no card fingerprint" do
      create_list(:payment_method, 10, unique_number_identifier: nil, customer: nil)

      assert_equal 0, PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days.count
    end

    test "excludes payment methods that have been manually reviewed" do
      create_list(:payment_method, 5, unique_number_identifier: "123456789", customer: nil)

      assert PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days.any?

      PaymentMethod.update_all(manually_reviewed_at: Time.zone.now)

      refute PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days.any?
    end

    test "excludes payment methods linked to suspended users" do
      5.times do
        user = create(:suspended_user)
        create(:payment_method, unique_number_identifier: "123456789", customer: nil, user: user)
      end

      refute PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days.any?
    end

    test "includes payment method that has more than 5 identical card fingerprints based on the unique_number_identifier in the last 30 days" do
      create_list(:payment_method, 5, unique_number_identifier: "9876542321", paypal_email: nil, created_at: 31.days.ago, customer: nil)
      create_list(:payment_method, 5, unique_number_identifier: "123456789", paypal_email: nil, customer: nil)
      create_list(:payment_method, 4, unique_number_identifier: "123", paypal_email: nil, customer: nil)

      matches = PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days

      assert_equal 1, matches.count
      result = T.must(matches.first)
      assert_equal result.card_fingerprint, "123456789"
      assert_equal result.count, 5
    end

    test "includes payment method that has more than 5 identical card fingerprints based on the paypal_email in the last 30 days" do
      create_list(:payment_method, 5, paypal_email: "user1@example.com", unique_number_identifier: nil, created_at: 31.days.ago, customer: nil)
      create_list(:payment_method, 5, paypal_email: "user2@example.com", unique_number_identifier: nil, customer: nil)
      create_list(:payment_method, 4, paypal_email: "user3@example.com", unique_number_identifier: nil, customer: nil)

      matches = PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days

      assert_equal 1, matches.count
      result = T.must(matches.first)
      assert_equal result.card_fingerprint, "user2@example.com"
      assert_equal result.count, 5
    end
  end

  context "for_purpose scope" do
    test "includes only payment methods for sponsors when purpose is :sponsors" do
      sponsors_customer = create(:customer, purpose: :sponsors)
      general_customer = create(:customer)

      sponsors_payment_method = create(:payment_method, customer: sponsors_customer)
      general_payment_method = create(:payment_method, customer: general_customer)
      no_customer_payment_method = create(:payment_method, customer: nil)

      result = PaymentMethod.for_purpose(:sponsors)

      assert_includes result, sponsors_payment_method
      refute_includes result, general_payment_method
      refute_includes result, no_customer_payment_method
    end

    test "includes all non-sponsors payment methods when purpose is :general" do
      sponsors_customer = create(:customer, purpose: :sponsors)
      general_customer = create(:customer)

      sponsors_payment_method = create(:payment_method, customer: sponsors_customer)
      general_payment_method = create(:payment_method, customer: general_customer)
      no_customer_payment_method = create(:payment_method, customer: nil)

      result = PaymentMethod.for_purpose(:general)

      refute_includes result, sponsors_payment_method
      assert_includes result, general_payment_method
      assert_includes result, no_customer_payment_method
    end
  end

  context "#assign_from_zuora_payment_method" do
    test "sets details from given Zuora payment method" do
      payment_method = PaymentMethod.new
      zuora_payment_method = with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        Billing::Zuora::PaymentMethod.find("2c92c0f866536dab01665f17918e0892")
      end
      fake_braintree_payment_method = stub(unique_number_identifier: "a nice unique value")
      Braintree::PaymentMethod.stubs(:find).returns(fake_braintree_payment_method)

      payment_method.assign_from_zuora_payment_method(zuora_payment_method)

      assert_equal "************1111", payment_method.truncated_number
      assert_equal 5, payment_method.expiration_month
      assert_equal 2023, payment_method.expiration_year
      assert_equal "Visa", payment_method.card_type
      assert_equal "a nice unique value", payment_method.unique_number_identifier
    end
  end

  test "initialize with credit card payment details" do
    payment_method = PaymentMethod.build_from_payment_details(encrypted_credit_card_params)

    refute_nil payment_method.country
    refute_nil payment_method.region
    refute_nil payment_method.postal_code

    # encrypted
    refute_nil payment_method.encrypted_expiration_month
    refute_nil payment_method.encrypted_expiration_year
    refute_nil payment_method.card_number
    refute_nil payment_method.cvv

    assert_nil payment_method.customer
    assert_nil payment_method.user
    assert_nil payment_method.payment_processor_customer_id
    assert_nil payment_method.payment_token
    assert_nil payment_method.truncated_number
    assert_nil payment_method.card_type

    assert_equal 0, payment_method.expiration_reminders
  end

  test "initialize with paypal payment details" do
    payment_method = PaymentMethod.build_from_payment_details \
      paypal_nonce: Braintree::Test::Nonce::PayPalFuturePayment,
      billing_address: billing_address_params

    refute_nil payment_method.paypal_nonce
  end

  context "#expiring_in_less_than_three_weeks?" do
    test "true when payment method is expiring in less than three weeks" do
      payment_method = create :payment_method,
        expiration_month: 8,
        expiration_year: 2016

      Timecop.freeze(GitHub::Billing.timezone.parse("July 20 2015")) do
        refute payment_method.expiring_in_less_than_three_weeks?
      end

      Timecop.freeze(GitHub::Billing.timezone.parse("July 1 2016")) do
        refute payment_method.expiring_in_less_than_three_weeks?
      end

      Timecop.freeze(GitHub::Billing.timezone.parse("July 11 2016")) do
        assert payment_method.expiring_in_less_than_three_weeks?
      end

      Timecop.freeze(GitHub::Billing.timezone.parse("August 2 2016")) do
        assert payment_method.expiring_in_less_than_three_weeks?
      end
    end
  end

  context "#update" do
    test "logs when update failed for user" do
      with_live_zuora("zuora/paypal/braintree_failed_create_payment_method") do
        events         = subscribe "payment_method.update"
        payment_method = create(:payment_method, :zuora)
        result         = payment_method.update_payment_details(encrypted_credit_card_params)

        refute result.success?
        expected_payload = {
          user: payment_method.user.login,
          user_id: payment_method.user_id,
          actor: payment_method.user.login,
          actor_id: payment_method.user_id,
          payment_processor_customer_id: "66170868",
          payment_processor_type: "zuora",
          payment_method: "card",
        }

        assert event = events.pop, "an event was expected"

        # The note field is going to be dynamic, by design.
        assert_equal expected_payload, event.payload.except(:note)
        assert_match /Error Updating: [a-zA-Z]+/, event.payload[:note]

        refute events.pop
      end
    end

    test "logs when update failed for business" do
      with_live_zuora("zuora/paypal/braintree_failed_create_payment_method") do
        events = subscribe "payment_method.update"
        business = create(:business)
        actor = business.owners.first
        payment_method = create(:payment_method, :zuora, user: nil, customer: business.customer)
        result = payment_method.update_payment_details(encrypted_credit_card_params.merge(actor: actor))

        refute result.success?
        expected_payload = {
          business: business.slug,
          business_id: business.id,
          actor: business.owners.first.login,
          actor_id: business.owners.first.id,
          payment_processor_customer_id: "66170868",
          payment_processor_type: "zuora",
          payment_method: "card",
        }

        assert event = events.pop, "an event was expected"

        # The note field is going to be dynamic, by design.
        assert_equal expected_payload, event.payload.except(:note)
        assert_match /Error Updating: [a-zA-Z]+/, event.payload[:note]

        refute events.pop
      end
    end

    test "customer with new credit card for user" do
      with_live_zuora("braintree/successful_update_credit_card") do
        events         = subscribe "payment_method.update"
        payment_method = create :payment_method, payment_processor_type: :braintree
        result         = payment_method.update_payment_details(encrypted_credit_card_params)

        assert result.success?
        assert_equal "400934******1881", payment_method.truncated_number
        assert_equal 0, payment_method.expiration_reminders
        refute_nil payment_method.unique_number_identifier

        expected_payload = {
          user: payment_method.user.login,
          user_id: payment_method.user_id,
          actor: payment_method.user.login,
          actor_id: payment_method.user_id,
          note: "Updated credit card",
          payment_processor_customer_id: "66170868",
          payment_processor_type: "braintree",
          payment_method: "card",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "customer with new credit card for business" do
      with_live_zuora("braintree/successful_update_credit_card") do
        events = subscribe "payment_method.update"
        business = create(:business)
        actor = business.owners.first
        payment_method = (
          create :payment_method,
          payment_processor_type: :braintree,
          user: nil,
          customer: business.customer
        )
        result = payment_method.update_payment_details(encrypted_credit_card_params.merge(actor: actor))

        assert result.success?
        assert_equal "400934******1881", payment_method.truncated_number
        assert_equal 0, payment_method.expiration_reminders
        refute_nil payment_method.unique_number_identifier

        expected_payload = {
          business: business.slug,
          business_id: business.id,
          actor: business.owners.first.login,
          actor_id: business.owners.first.id,
          note: "Updated credit card",
          payment_processor_customer_id: "66170868",
          payment_processor_type: "braintree",
          payment_method: "card",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "resets expiration_reminders" do
      user = create(:user)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/payment_processors/successful_credit_card_update_payment_details") do
        user.reload

        payment_method = user.payment_method
        result = payment_method.update_payment_details(zuora_parsed_payment_details)

        assert result.success?
        assert_equal "************1111", payment_method.truncated_number
        assert_equal 0, payment_method.expiration_reminders
      end
    end

    test "blocklisted? is true if payment method has already been blacklisted" do
      with_live_zuora("braintree/successful_update_credit_card") do
        payment_method = create :payment_method,
          unique_number_identifier: "eb1fde61fcb0d1b0f350d11b43163a6f"
        create :blacklisted_payment_method,
          unique_number_identifier: payment_method.unique_number_identifier

        payment_method.update_payment_details(encrypted_credit_card_params)
        assert payment_method.blocklisted?
      end
    end

    test "doesn't instrument on expiration_reminders update" do
      payment_method = create :payment_method
      events = subscribe "payment_method.update"
      payment_method.increment!(:expiration_reminders)
      refute events.pop
    end

    test "requires payment details" do
      with_live_zuora("braintree/successful_update_credit_card") do
        assert_raises ArgumentError do
          create(:payment_method).update_payment_details({})
        end
      end
    end

    test "customer fails" do
      events = subscribe "payment_method.update"

      with_live_zuora("braintree/failed_update_credit_card") do
        payment_method = create :payment_method
        result = payment_method.update_payment_details(encrypted_credit_card_params)

        refute result.success?
      end
    end

    test "customer with new paypal" do
      user = create(:user)
      with_live_zuora("braintree/successful_update_paypal_customer") do
        events = subscribe "payment_method.update"
        payment_method = create :payment_method, payment_processor_customer_id: 82609601,
          region: "California", postal_code: "94107", country: "USA", payment_processor_type: :braintree
        result = payment_method.update_payment_details(
          paypal_nonce: Braintree::Test::Nonce::PayPalFuturePayment)

        assert result.success?
        assert payment_method.paypal?
        refute payment_method.credit_card?
        assert_equal "jane.doe@example.com", payment_method.paypal_email
        assert_equal "California", payment_method.region
        assert_equal "94107", payment_method.postal_code
        assert_equal "USA", payment_method.country

        expected_payload = {
          user: payment_method.user.login,
          user_id: payment_method.user_id,
          actor: payment_method.user.login,
          actor_id: payment_method.user_id,
          note: "Updated PayPal account",
          payment_processor_customer_id: "82609601",
          payment_processor_type: "braintree",
          payment_method: "paypal",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "enterprise customer with new paypal" do
      admin = create(:user)
      business = create(:business, owners: [admin])
      with_live_zuora("braintree/successful_update_paypal_customer") do
        events = subscribe "payment_method.update"
        payment_method = create :payment_method, payment_processor_customer_id: 82609601,
          region: "California", postal_code: "94107", country: "USA", payment_processor_type: :braintree,
          customer: business.customer
        result = payment_method.update_payment_details(
          paypal_nonce: Braintree::Test::Nonce::PayPalFuturePayment,
          actor: admin,
        )

        assert result.success?
        assert payment_method.paypal?
        refute payment_method.credit_card?
        assert_equal "California", payment_method.region
        assert_equal "94107", payment_method.postal_code
        assert_equal "USA", payment_method.country

        expected_payload = {
          business: business.slug,
          business_id: business.id,
          actor: admin.login,
          actor_id: admin.id,
          note: "Updated PayPal account",
          payment_processor_customer_id: "82609601",
          payment_processor_type: "braintree",
          payment_method: "paypal",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "customer with new paypal sets address" do
      user = create(:user)
      with_live_zuora("braintree/successful_update_paypal_customer") do
        events = subscribe "payment_method.update"
        payment_method = create :payment_method, payment_processor_customer_id: 82609601, payment_processor_type: :braintree
        result = payment_method.update_payment_details(
          paypal_nonce: Braintree::Test::Nonce::PayPalFuturePayment,
          billing_address: billing_address_params)

        assert result.success?
        assert payment_method.paypal?
        refute payment_method.credit_card?
        assert_equal "jane.doe@example.com", payment_method.paypal_email
        assert_equal "California", payment_method.region
        assert_equal "94107", payment_method.postal_code
        assert_equal "USA", payment_method.country

        expected_payload = {
          user: payment_method.user.login,
          user_id: payment_method.user_id,
          actor: payment_method.user.login,
          actor_id: payment_method.user_id,
          note: "Updated PayPal account",
          payment_processor_customer_id: "82609601",
          payment_processor_type: "braintree",
          payment_method: "paypal",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "enterprise customer with new paypal sets address" do
      admin = create(:user)
      business = create(:business, owners: [admin])
      with_live_zuora("braintree/successful_update_paypal_customer") do
        events = subscribe "payment_method.update"
        payment_method = create :payment_method, payment_processor_customer_id: 82609601,
          payment_processor_type: :braintree, customer: business.customer
        result = payment_method.update_payment_details(
          paypal_nonce: Braintree::Test::Nonce::PayPalFuturePayment,
          actor: admin,
          billing_address: billing_address_params)

        assert result.success?
        assert payment_method.paypal?
        refute payment_method.credit_card?
        assert_equal "jane.doe@example.com", payment_method.paypal_email
        assert_equal "California", payment_method.region
        assert_equal "94107", payment_method.postal_code
        assert_equal "USA", payment_method.country

        expected_payload = {
          business: business.slug,
          business_id: business.id,
          actor: admin.login,
          actor_id: admin.id,
          note: "Updated PayPal account",
          payment_processor_customer_id: "82609601",
          payment_processor_type: "braintree",
          payment_method: "paypal",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end
  end

  context "#clear_payment_details" do
    test "clears payment method fields with Zuora processor success" do
      with_live_zuora("zuora/remove_all_payment_methods") do
        events = subscribe "payment_method.remove"

        zuora_account_id = "2c92c0fa61789dac01619105be872892"
        payment_method = create :payment_method, payment_processor_customer_id: zuora_account_id, payment_processor_type: "zuora"
        assert payment_method.clear_payment_details(payment_method.user)

        assert_equal zuora_account_id, payment_method.payment_processor_customer_id
        assert_equal "payment-token-cleared", payment_method.payment_token
        assert_nil payment_method.truncated_number
        assert_nil payment_method.expiration_month
        assert_nil payment_method.expiration_year
        assert_nil payment_method.card_type
        assert_nil payment_method.paypal_email
        assert_nil payment_method.unique_number_identifier
        assert_equal 0, payment_method.expiration_reminders
        # want to keep these
        refute_nil payment_method.country
        refute_nil payment_method.region
        refute_nil payment_method.postal_code

        refute payment_method.credit_card?
        refute payment_method.paypal?

        expected_payload = {
          user: payment_method.user.login,
          user_id: payment_method.user_id,
          actor: payment_method.user.login,
          actor_id: payment_method.user_id,
          note: "Removed payment details",
          payment_processor_customer_id: zuora_account_id,
          payment_processor_type: payment_method.payment_processor_type,
          payment_method: "none",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "customer payment details" do
      with_live_zuora("zuora/remove_all_payment_methods") do
        events = subscribe "payment_method.remove"

        payment_method = create :payment_method, payment_processor_customer_id: "28837421",
          payment_processor_type: :zuora
        assert payment_method.clear_payment_details(payment_method.user)

        assert_equal "28837421", payment_method.payment_processor_customer_id
        assert_equal "payment-token-cleared", payment_method.payment_token
        assert_nil payment_method.truncated_number
        assert_nil payment_method.expiration_month
        assert_nil payment_method.expiration_year
        assert_nil payment_method.card_type
        assert_nil payment_method.paypal_email
        assert_nil payment_method.unique_number_identifier
        assert_equal 0, payment_method.expiration_reminders
        # want to keep these
        refute_nil payment_method.country
        refute_nil payment_method.region
        refute_nil payment_method.postal_code

        refute payment_method.credit_card?
        refute payment_method.paypal?

        expected_payload = {
          user: payment_method.user.login,
          user_id: payment_method.user_id,
          actor: payment_method.user.login,
          actor_id: payment_method.user_id,
          note: "Removed payment details",
          payment_processor_customer_id: "28837421",
          payment_processor_type: "zuora",
          payment_method: "none",
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
        refute events.pop
      end
    end

    test "does not report exception if payment method already deleted" do
      with_live_zuora("braintree/remove_all_payment_methods") do
        payment_method = create :payment_method,
          payment_processor_type: "braintree",
          payment_processor_customer_id: "28837421"
        Braintree::PaymentMethod
          .expects(:delete)
          .raises(Braintree::NotFoundError)
        Failbot.expects(:report).never

        assert payment_method.clear_payment_details(payment_method.user)
      end
    end
  end

  context ".expiring_credit_cards" do
    test "next month" do
      one_month_from_now = GitHub::Billing.today + 1.month
      user = create :credit_card_user
      user.payment_method.update \
        expiration_month: one_month_from_now.month,
        expiration_year: one_month_from_now.year

      expiring = PaymentMethod.expiring_credit_cards
      assert_equal 1, expiring.count
      assert_equal user, T.must(T.must(expiring.first).customer).users.first
    end

    test "on year boundary" do
      Timecop.freeze(GitHub::Billing.timezone.local(2014, 12, 1)) do
        user = create :credit_card_user
        user.payment_method.update \
          expiration_month: 1,
          expiration_year: 2015

        expiring = PaymentMethod.expiring_credit_cards
        assert_equal 1, expiring.count
        assert_equal user, T.must(T.must(expiring.first).customer).users.first
      end
    end
  end

  context "validates_presence_of_user_or_customer" do
    test "requires a payment to have a user or customer" do
      method = create :payment_method
      method.user = nil
      method.customer = nil

      assert_raises ActiveRecord::RecordInvalid do
        method.save!
      end
    end

    test "is fine with only a customer" do
      method = create :payment_method
      method.user = nil

      assert_equal true, method.save
    end
  end

  context "to_s" do
    test "includes card type and formatted number for valid credit card" do
      method = create :payment_method
      expected = "Visa 4*** **** **** 1111"
      assert_equal expected, method.to_s
    end

    test "returns PayPal email for PayPal payment method" do
      method = create :paypal_payment_method
      assert_equal method.paypal_email, method.to_s
    end

    test "returns invalid if payment token is not valid" do
      method = create :no_credit_card_payment_method
      assert_equal "invalid payment method", method.to_s
    end
  end

  context "#manually_reviewed?" do
    test "when manually reviewed" do
      payment_method = create :payment_method, manually_reviewed_at: Time.zone.now, manually_reviewed_by_id: 1
      assert payment_method.manually_reviewed?
    end

    test "when not manually reviewed" do
      payment_method = create :payment_method, manually_reviewed_at: nil, manually_reviewed_by_id: nil
      refute payment_method.manually_reviewed?
    end
  end

  context "#external_payment_method_consecutive_failure_count" do
    test "returns NumConsecutiveFailures from Zuora" do
      stub_zuora
      payment_method = build(:payment_method)

      GitHub
        .zuorest_client
        .expects(:get_payment_method)
        .with(payment_method.payment_token)
        .returns({ "NumConsecutiveFailures" => 2 })

      assert_equal 2, payment_method.external_payment_method_consecutive_failure_count
    end

    test "returns nil when payment_method was cleared" do
      payment_method = build(:payment_method, payment_token: PaymentMethod::PAYMENT_TOKEN_CLEARED)

      assert_nil payment_method.external_payment_method_consecutive_failure_count
    end
  end

  context "#update_rbi_auto_pay_on_country_change" do
    test "changing country from IND to another re-enables auto pay" do
      user = create :user, :disabled_by_india_rbi

      user.payment_method.update country: "USA"

      refute user.reload.customer.autopay_disabled_by_india_rbi?
    end

    test "doesn't update auto pay when country changes to IND" do
      user = create :credit_card_user
      user.disable_auto_pay! :india_rbi

      user.payment_method.update country: "IND"

      assert user.reload.customer.autopay_disabled_by_india_rbi?
    end

    test "doesn't attempt to update auto pay for users with auto pay enabled" do
      user = create :india_based_credit_card_user

      User.any_instance.expects(:enable_auto_pay!).never

      user.payment_method.update country: "USA"
    end
  end

  context "#card_fingerprint" do
    test "returns the expected card fingerprint" do
      stripe_payment_method = create :payment_method, unique_number_identifier: "abc", paypal_email: nil
      assert_equal stripe_payment_method.card_fingerprint, "abc"

      paypal_payment_method = create :payment_method, paypal_email: "user1@example.com", unique_number_identifier: nil
      assert_equal paypal_payment_method.card_fingerprint, "user1@example.com"

      fingerprintless_payment_method = create :payment_method, unique_number_identifier: nil, paypal_email: nil
      assert_nil fingerprintless_payment_method.card_fingerprint
    end
  end
end
