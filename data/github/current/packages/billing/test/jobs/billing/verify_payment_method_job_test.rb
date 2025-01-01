# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::VerifyPaymentMethodJobTest < GitHub::TestCase
  test "does nothing if the provided payment method token does not match the one on the account" do
    user = create(:credit_card_user, :zuora)

    GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect).never

    GitHub.zuorest_client.class.any_instance.expects(:query_action).never

    Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform).never

    GitHub::Billing.expects(:transition_to_external_subscription).never

    Billing::VerifyPaymentMethodJob.perform_now(user, "some-other-payment-token")
  end

  test "handles errors when an error occurs while fetching the metered usage amount for authorization" do
    user = create(:credit_card_user, :zuora)
    user.customer.update(billed_via_billing_platform: true)

    GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
      .with({ accountKey: user.customer.zuora_account_id })
      .returns({
        "success" => false,
        "processId" => "6B112EA2F53ED7E0",
        "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
        "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
      })
      .once

    GitHub.zuorest_client.class.any_instance.expects(:query_action)
      .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
      .returns({ "size" => 0, "records" => [], "done" => true })

    Billing::Platform::Api::Client.any_instance.expects(:get_net_usage_line_items)
      .returns(Billing::Platform::Api::Error.new("boom"))
      .once

    Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform)
      .with(
        entity_id: user.id,
        amount_in_cents: 100,
        unlock_billing_on_success: false,
        reset_billing_attempts_when_unlocked: false,
        is_business: false,
        skip_account_age_check: true,
        origin: "Billing::VerifyPaymentMethodJob"
      )
      .returns(false)
      .once

    GitHub::Billing.expects(:transition_to_external_subscription).never

    assert_nothing_raised do
      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end

    assert_equal(1, Failbot.reports.size)
  end

  context "authorization amounts" do
    test "authorizes for $1 when there are no previous authorizations or metered usage" do
      enable_feature_flag(:billing_reauth_last_amount_on_payment_method_update)
      user = create(:credit_card_user, :with_billing_locked, :zuora, billing_attempts: 3)
      create(:billing_transaction, :authorization, :failed, amount_in_cents: 9999, user: user, created_at: 2.hours.ago)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "6B112EA2F53ED7E0",
          "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
          "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 0, "records" => [], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform)
        .with(
          entity_id: user.id,
          amount_in_cents: 100,
          unlock_billing_on_success: false,
          reset_billing_attempts_when_unlocked: false,
          is_business: false,
          skip_account_age_check: true,
          origin: "Billing::VerifyPaymentMethodJob"
        )
        .returns(true)
        .once

      GitHub::Billing.expects(:transition_to_external_subscription)
        .with(user)
        .once

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end

    test "authorizes for the amount of the last authorization performed in the past hour" do
      enable_feature_flag(:billing_reauth_last_amount_on_payment_method_update)
      user = create(:credit_card_user, :with_billing_locked, :zuora, billing_attempts: 3)
      create(:billing_transaction, :authorization, :failed, amount_in_cents: 9999, user: user, created_at: 59.minutes.ago)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "6B112EA2F53ED7E0",
          "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
          "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 0, "records" => [], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform)
        .with(
          entity_id: user.id,
          amount_in_cents: 9999,
          unlock_billing_on_success: false,
          reset_billing_attempts_when_unlocked: false,
          is_business: false,
          skip_account_age_check: true,
          origin: "Billing::VerifyPaymentMethodJob"
        )
        .returns(true)
        .once

      GitHub::Billing.expects(:transition_to_external_subscription)
        .with(user)
        .once

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end
  end

  context "when the payment method is valid" do
    test "does not save temporary budgets when reinstating billing locked accounts after a successful authorization" do
      user = create(:credit_card_user, :with_billing_locked, :zuora, billing_attempts: 3)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "6B112EA2F53ED7E0",
          "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
          "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 0, "records" => [], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform)
        .with(
          entity_id: user.id,
          amount_in_cents: 100,
          unlock_billing_on_success: false,
          reset_billing_attempts_when_unlocked: false,
          is_business: false,
          skip_account_age_check: true,
          origin: "Billing::VerifyPaymentMethodJob"
        )
        .returns(true)
        .once

      GitHub::Billing.expects(:transition_to_external_subscription)
        .with(user)
        .once

      # Make some unrelated changes that shouldn't be saved
      user.billing_extra = "test"

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)

      user.reload
      assert user.enabled?
      assert_equal 0, user.billing_attempts
      refute_equal "test", user.billing_extra
    end

    test "reinstates billing locked accounts and creates an external subscription when payment collection is successful" do
      user = create(:credit_card_user, :with_billing_locked, :zuora, billing_attempts: 3)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "invoices" => [{ "invoiceId" => "some-invoice-id", "invoiceNumber" => "INV12345678", "invoiceAmount" => 4.0 }],
          "paymentId" => "some-payment-id",
          "amountCollected" => 4.0,
          "success" => true
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action).never

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform).never

      GitHub::Billing.expects(:transition_to_external_subscription)
        .with(user)
        .once

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)

      user.reload
      assert user.enabled?
      assert_equal 0, user.billing_attempts
    end

    test "reinstates billing locked accounts and creates an external subscription when there are no invoices to collect, no previous successful payments, and authorization is successful" do
      user = create(:credit_card_user, :with_billing_locked, :zuora, billing_attempts: 3)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "6B112EA2F53ED7E0",
          "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
          "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 0, "records" => [], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform)
        .with(
          entity_id: user.id,
          amount_in_cents: 100,
          unlock_billing_on_success: false,
          reset_billing_attempts_when_unlocked: false,
          is_business: false,
          skip_account_age_check: true,
          origin: "Billing::VerifyPaymentMethodJob"
        )
        .returns(true)
        .once

      GitHub::Billing.expects(:transition_to_external_subscription)
        .with(user)
        .once

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)

      user.reload
      assert user.enabled?
      assert_equal 0, user.billing_attempts
    end

    test "does nothing when there are no invoices to collect and there are previous successful payments" do
      user = create(:credit_card_user, :zuora)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "6B112EA2F53ED7E0",
          "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
          "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 1, "records" => [{ "Id" => "8a128514950233a901950dad271c35e7" }], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform).never

      GitHub::Billing.expects(:transition_to_external_subscription).never

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end

    test "does nothing when there are no invoices to collect, no previous successful payments, and the account trust tier is TRUSTED" do
      user = create(:credit_card_user, :zuora)
      user.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "6B112EA2F53ED7E0",
          "reasons" => [{ "code" => 54000022, "message" => "Payment amount should be bigger than zero." }],
          "requestId" => "fc38869e-d7c9-4b50-ba72-540a89856e72"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 0, "records" => [], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform).never

      GitHub::Billing.expects(:transition_to_external_subscription).never

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end
  end

  context "when the payment method is not valid" do
    test "does not create an external subscription or perform an authorization when payment collection fails due to a decline" do
      user = create(:credit_card_user, :zuora)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "E9CE6DF8C6CD197B",
          "reasons" => [{ "code" => 54000099, "message" => "{\"gatewayResponse\":{\"code\":\"402\",\"message\":\"[card_error/card_declined/generic_decline] Your card was declined.\"}}" }],
          "requestId" => "4eeac749-1430-4691-ba65-80e9936308c3"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action).never

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform).never

      GitHub::Billing.expects(:transition_to_external_subscription).never

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end

    test "does not create an external subscription when payment collection fails due to a non-declined reason, there are no previous successful payments, and the authorization fails" do
      user = create(:credit_card_user, :zuora)

      GitHub.zuorest_client.class.any_instance.expects(:create_invoice_collect)
        .with({ accountKey: user.customer.zuora_account_id })
        .returns({
          "success" => false,
          "processId" => "E9CE6DF8C6CD197B",
          "reasons" => [{ "code" => 53500060, "message" => "Oops, internal error occurred, please try it again, and if it still doesn't work, please contact Zuora support." }],
          "requestId" => "4eeac749-1430-4691-ba65-80e9936308c3"
        })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:query_action)
        .with(queryString: "select Id from Payment where PaymentMethodId = '#{user.payment_method.payment_token}' and Status = 'Processed'")
        .returns({ "size" => 0, "records" => [], "done" => true })

      Billing::CreateAuthorizationBillingTransactionJob.any_instance.expects(:perform)
        .with(
          entity_id: user.id,
          amount_in_cents: 100,
          unlock_billing_on_success: false,
          reset_billing_attempts_when_unlocked: false,
          is_business: false,
          skip_account_age_check: true,
          origin: "Billing::VerifyPaymentMethodJob"
        )
        .returns(false)
        .once

      GitHub::Billing.expects(:transition_to_external_subscription).never

      Billing::VerifyPaymentMethodJob.perform_now(user, user.payment_method.payment_token)
    end
  end
end if GitHub.billing_enabled?
