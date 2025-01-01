# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::CreateBillingTransactionTest < GitHub::BillingTestCase
    include GitHub::ZuoraTestHelper

    context ".perform with Zuora::Payment" do
      test "creates a new BillingTransaction for a failed Paypal transaction" do
        FakeZuora.mock
        user = create(:paypal_user)

        plan_subscription = create(:billing_plan_subscription, user: user)
        service_ends_at = Date.new(2018, 4, 13)

        zuorest_payment = Zuorest::Model::Payment.new(
          Id: "2c92c0fa6205232601622035ebfc5334",
          Amount: 7.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Paypal",
          GatewayState: "NotSubmitted",
          PaymentNumber: "P-000001",
          ReferenceId: nil,
        )
        Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(7_00))
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
        assert_difference "user.reload.billing_transactions.count", 1 do
          billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: service_ends_at,
            zuora_transaction: zuora_payment
        end
        billing_transaction = T.must(billing_transaction)

        assert_equal user, billing_transaction.user
        assert_equal plan_subscription, billing_transaction.plan_subscription
        assert_equal "first-time-paid-upgrade", billing_transaction.transaction_type
        assert_equal 7_00, billing_transaction.amount_in_cents
        assert_equal Time.parse("2018-03-13T09:33:47.000-07:00"), billing_transaction.created_at
        assert_equal zuora_payment.payment_number, billing_transaction.transaction_id
        assert billing_transaction.paypal?
        assert_equal service_ends_at, billing_transaction.service_ends_at&.to_date
        assert billing_transaction.processor_declined?
        assert billing_transaction.zuora?
        assert_equal "2c92c0fa6205232601622035ebfc5334", billing_transaction.platform_transaction_id
      end

      test "creates a new user BillingTransaction for the first charge" do
        user = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, user: user)
        service_ends_at = Date.new(2018, 4, 13)

        zuorest_payment = Zuorest::Model::Payment.new(
          Id: "2c92c0fa6205232601622035ebfc5334",
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
        with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          assert_difference "user.reload.billing_transactions.count", 1 do
            billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
              plan_subscription,
              service_ends_at: service_ends_at,
              zuora_transaction: zuora_payment
          end
        end
        billing_transaction = T.must(billing_transaction)

        assert_equal user, billing_transaction.user
        assert_equal plan_subscription, billing_transaction.plan_subscription
        assert_equal user.customer.id, billing_transaction.customer_id
        assert_equal "first-time-paid-upgrade", billing_transaction.transaction_type
        assert_equal 10_00, billing_transaction.amount_in_cents
        assert_equal Time.parse("2018-03-13T09:33:47.000-07:00"), billing_transaction.created_at
        assert_equal "jgdxs6", billing_transaction.transaction_id
        assert billing_transaction.credit_card?
        assert_equal "411111", billing_transaction.bank_identification_number.to_s
        assert_equal "1111", billing_transaction.last_four
        assert_equal "Unknown", billing_transaction.country_of_issuance
        assert_equal service_ends_at, billing_transaction.service_ends_at&.to_date
        assert billing_transaction.settled?
        assert_equal "2012-04-27_Github", billing_transaction.settlement_batch_id
        assert_equal %w[authorized submitted_for_settlement settled],
          billing_transaction.statuses.map(&:status)
        assert billing_transaction.zuora?
        assert_equal "2c92c0fa6205232601622035ebfc5334", billing_transaction.platform_transaction_id
      end

      test "creates a new business BillingTransaction for the first charge" do
        business = create(:business, customer: create(:customer, :zuora, billing_type: "card"))
        customer = business.customer
        plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)
        service_ends_at = Date.new(2018, 4, 13)

        zuorest_payment = Zuorest::Model::Payment.new(
          Id: "2c92c0fa6205232601622035ebfc5334",
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
        with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          assert_difference "business.reload.billing_transactions.count", 1 do
            billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
              plan_subscription,
              service_ends_at: service_ends_at,
              zuora_transaction: zuora_payment
          end
        end
        billing_transaction = T.must(billing_transaction)

        assert_equal business, billing_transaction.business
        assert_equal plan_subscription, billing_transaction.plan_subscription
        assert_equal business.customer_id, billing_transaction.customer_id
        assert_equal "first-time-paid-upgrade", billing_transaction.transaction_type
        assert_equal 10_00, billing_transaction.amount_in_cents
        assert_equal Time.parse("2018-03-13T09:33:47.000-07:00"), billing_transaction.created_at
        assert_equal "jgdxs6", billing_transaction.transaction_id
        assert billing_transaction.credit_card?
        assert_equal "411111", billing_transaction.bank_identification_number.to_s
        assert_equal "1111", billing_transaction.last_four
        assert_equal "Unknown", billing_transaction.country_of_issuance
        assert_equal service_ends_at, billing_transaction.service_ends_at&.to_date
        assert billing_transaction.settled?
        assert_equal "2012-04-27_Github", billing_transaction.settlement_batch_id
        assert_equal %w[authorized submitted_for_settlement settled],
          billing_transaction.statuses.map(&:status)
        assert billing_transaction.zuora?
        assert_equal "2c92c0fa6205232601622035ebfc5334", billing_transaction.platform_transaction_id
      end

      test "creates a new user BillingTransaction for a recurring charge" do
        user = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, user: user)

        create :billing_transaction,
          user: user,
          transaction_type: "first-time-paid-upgrade",
          last_status: :settled

        Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
        zuorest_payment = Zuorest::Model::Payment.new(
          Id: SecureRandom.hex(12),
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: Date.new(2018, 4, 13),
            zuora_transaction: zuora_payment
        end

        assert_equal user, billing_transaction.user
        assert_equal plan_subscription, billing_transaction.plan_subscription
        assert_equal "recurring-charge", billing_transaction.transaction_type
        assert_empty billing_transaction.line_items
      end

      test "creates a new business BillingTransaction for a recurring charge" do
        business = create(:business, customer: create(:customer, :zuora, billing_type: "card"))
        customer = business.customer
        plan_subscription = create(:billing_plan_subscription, :business_owned, customer: customer)
        service_ends_at = Date.new(2018, 4, 13)

        create :billing_transaction,
          :business_owned,
          plan_subscription: plan_subscription,
          customer: customer,
          transaction_type: "first-time-paid-upgrade",
          last_status: :settled

        Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
        zuorest_payment = Zuorest::Model::Payment.new(
          Id: SecureRandom.hex(12),
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: service_ends_at,
            zuora_transaction: zuora_payment
        end

        assert_equal business, billing_transaction.business
        assert_equal plan_subscription, billing_transaction.plan_subscription
        assert_equal "recurring-charge", billing_transaction.transaction_type
        assert_empty billing_transaction.line_items
      end

      test "creates a new BillingTransaction with prorate charge type for plan change" do
        user = create(:credit_card_user, plan: GitHub::Plan.pro)
        plan_subscription = create(:billing_plan_subscription, user: user)

        with_live_zuora("zuora/get_plan_prorated_payment") do
          payment = Billing::Zuora::Payment.find("2c92c0f9661ff98001662178d2ea7ec9")

          billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: Date.new(2018, 4, 13),
            zuora_transaction: payment

          assert_equal user, billing_transaction.user
          assert_equal plan_subscription, billing_transaction.plan_subscription
          assert_equal "prorate-charge", billing_transaction.transaction_type
        end
      end

      # see https://github.com/github/sponsors/issues/4500
      test "creates a new BillingTransaction with recurring charge for Sponsors-invoiced customer's sponsorship" do
        sponsors_invoiced_org = create(:credit_card_org, :sponsors_invoiced, plan: GitHub::Plan.business_plus)
        sponsorship = create(:sponsorship, sponsor: sponsors_invoiced_org)
        user = sponsorship.sponsor
        plan_subscription = sponsorship.plan_subscription

        assert_predicate sponsors_invoiced_org, :sponsors_invoiced?
        customer = plan_subscription.customer
        assert_predicate customer, :sponsors_purpose?, "Sponsors-invoiced orgs use unique customers"

        create(:billing_transaction, user: user, transaction_type: "first-time-paid-upgrade")

        mock_payment = {
          "PaymentNumber": "P-00000797",
          "CreatedDate": "2018-03-13T09:33:47.000-07:00",
          "Gateway": "Stripe v2",
          "GatewayResponse": "Approved",
          "Id": "2c92c0f9661ff98001662178d2ea7ec9",
          "AppliedCreditBalanceAmount": 0,
          "RefundAmount": 0,
          "Amount": sponsorship.amount.dollars,
          "Status": "Processed",
        }

        zuorest_payment = Zuorest::Model::Payment.new(mock_payment)
        payment = Billing::Zuora::Payment.new(zuorest_payment)

        payment.stubs(:invoice_items).returns([
          Billing::Zuora::SubscribableInvoiceItem.new({
            "chargeId" => SecureRandom.alphanumeric(32),
            "unitPrice" => sponsorship.amount.dollars,
            "chargeName" => "charge-name",
            "chargeAmount" => sponsorship.amount.dollars,
            "quantity" => 1.0,
            "serviceStartDate" => "2018-03-13",
            "serviceEndDate" => "2018-04-13",
            "productRatePlanChargeId" => SecureRandom.alphanumeric(32),
          }, subscribable: sponsorship.tier)
        ])

        billing_transaction = PlanSubscription::CreateBillingTransaction.perform(plan_subscription,
          service_ends_at: Date.new(2018, 4, 13),
          zuora_transaction: payment,
        )

        assert_equal user, billing_transaction.user
        assert_equal plan_subscription, billing_transaction.plan_subscription
        assert_equal customer.id, billing_transaction.customer_id
        assert_equal "recurring-charge", billing_transaction.transaction_type
      end

      # https://github.com/github/sponsors/issues/4617
      test "creates a new BillingTransaction with a credit_balance_adjusted last_status for a credit balance adjustment" do
        org = create(:credit_card_organization)
        plan_subscription = create(:billing_plan_subscription, user: org)

        with_live_zuora("zuora/credit_balance_used_for_invoice_webhook") do
          # credit balance adjustment id from the cassette
          zuora_credit_balance_adjustment_id = "2c92c0f8748a8d3c01749388f597514a"
          cba = ::Billing::Zuora::CreditBalanceAdjustment.find(zuora_credit_balance_adjustment_id)

          billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: 1.month.from_now,
            zuora_transaction: cba

          assert_equal "credit_balance_adjusted", billing_transaction.last_status
        end
      end

      test "creates a new BillingTransaction with prorate days for plan change" do
        org = create(:credit_card_organization, plan: GitHub::Plan.business)
        plan_subscription = create(:billing_plan_subscription, user: org)

        with_live_zuora("zuora/get_plan_prorated_payment_with_service_period") do
          payment = Billing::Zuora::Payment.find("8ad086917c3012d7017c32a8105f7f8a")

          billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: Date.new(2021, 10, 05),
            zuora_transaction: payment

          assert_equal "prorate-seat-charge", billing_transaction.transaction_type
          assert_equal 6, billing_transaction.prorated_days
          assert_equal plan_subscription, billing_transaction.plan_subscription
        end
      end

      test "updates an existing user BillingTransaction" do
        user = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, user: user)

        existing_transaction = create :billing_transaction,
          user: user,
          plan_subscription: plan_subscription,
          transaction_type: "first-time-paid-upgrade",
          last_status: :submitted_for_settlement,
          transaction_id: "jgdxs6"

        zuorest_payment = Zuorest::Model::Payment.new(
          Id: SecureRandom.hex(12),
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
        with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          assert_difference "user.reload.billing_transactions.count", 0 do
            billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
              plan_subscription,
              service_ends_at: Date.new(2018, 4, 13),
              zuora_transaction: zuora_payment
          end
        end
        billing_transaction = T.must(billing_transaction)

        assert_equal existing_transaction.id, billing_transaction.id
        assert billing_transaction.settled?
      end

      test "updates an existing business BillingTransaction" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        business = plan_subscription.business
        customer = business.customer

        existing_transaction = create :billing_transaction,
          :business_owned,
          plan_subscription: plan_subscription,
          customer: customer,
          transaction_type: "first-time-paid-upgrade",
          last_status: :submitted_for_settlement,
          transaction_id: "jgdxs6"

        zuorest_payment = Zuorest::Model::Payment.new(
          Id: SecureRandom.hex(12),
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        billing_transaction = T.let(nil, T.nilable(Billing::BillingTransaction))
        with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          assert_difference "business.reload.billing_transactions.count", 0 do
            billing_transaction = PlanSubscription::CreateBillingTransaction.perform \
              plan_subscription,
              service_ends_at: Date.new(2018, 4, 13),
              zuora_transaction: zuora_payment
          end
        end
        billing_transaction = T.must(billing_transaction)

        assert_equal business, billing_transaction.business
        assert_equal existing_transaction.id, billing_transaction.id
        assert billing_transaction.settled?
      end

      test "tracks the BillingTransaction amount in GitHub stats" do
        user = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, user: user)

        zuorest_payment = Zuorest::Model::Payment.new(
          Id: SecureRandom.hex(12),
          Amount: 10.0,
          CreatedDate: "2018-03-13T09:33:47.000-07:00",
          Gateway: "Braintree",
          ReferenceId: "jgdxs6",
        )
        zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        with_live_zuora("braintree/find_credit_card_transaction_by_id") do
          PlanSubscription::CreateBillingTransaction.perform \
            plan_subscription,
            service_ends_at: Date.new(2018, 4, 13),
            zuora_transaction: zuora_payment
        end

        assert_equal 10_00, GitHub.dogstats.counts("cream").first.value
      end
    end

    test "raises throttling error when max retries have been exhausted" do
      user = create(:credit_card_user)
      plan_subscription = create(:billing_plan_subscription, user: user)
      create(:billing_transaction, user: user, transaction_type: "first-time-paid-upgrade", last_status: :settled)
      Billing::Pricing.any_instance.stubs(:discounted).returns(Billing::Money.new(10_00))
      zuorest_payment = Zuorest::Model::Payment.new(Id: SecureRandom.hex(12), Amount: 10.0, CreatedDate: "2018-03-13T09:33:47.000-07:00", Gateway: "Braintree", ReferenceId: "jgdxs6")
      zuora_payment = Billing::Zuora::Payment.new(zuorest_payment)

      max_retries = PlanSubscription::CreateBillingTransaction::MAX_THROTTLE_RETRIES
      GitHub::Throttler::Null.any_instance.expects(:throttle).times(max_retries + 1).raises(Freno::Throttler::Error)
      assert_raises(Freno::Throttler::Error) do
        PlanSubscription::CreateBillingTransaction.perform \
          plan_subscription,
          service_ends_at: Date.new(2018, 4, 13),
          zuora_transaction: zuora_payment
      end
    end
  end
end
