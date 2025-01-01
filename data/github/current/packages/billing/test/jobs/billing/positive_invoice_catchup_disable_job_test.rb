# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PositiveInvoiceCatchupDisableJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:credit_card_user)
    plan_subscription = create(:billing_plan_subscription, user: @user)
    @customer = plan_subscription.customer
  end

  test "it finds the relevant user account, turns the invoice amount to cents and sends that off to be processed " do
    invoice_amount = "14.00"
    expected_amount = Billing::Money.parse(invoice_amount).cents

    ::Billing::DisableAccountsWithUncollectableInvoices.expects(:perform).with(account: @user, amount: expected_amount)

    ::Billing::PositiveInvoiceCatchupDisableJob.perform_now(zuora_account_id: @customer.zuora_account_id, invoice_amount: invoice_amount)
  end

  test "it finds the relevant business account, turns the invoice amount to cents and sends that off to be processed " do
    business = create(:business, :with_self_serve_payment)
    plan_subscription = create(:billing_plan_subscription, :zuora, customer: business.customer, user: nil)
    customer = plan_subscription.customer

    invoice_amount = "14.00"
    expected_amount = Billing::Money.parse(invoice_amount).cents

    ::Billing::DisableAccountsWithUncollectableInvoices.expects(:perform).with(account: business, amount: expected_amount)

    ::Billing::PositiveInvoiceCatchupDisableJob.perform_now(zuora_account_id: customer.zuora_account_id, invoice_amount: invoice_amount)
  end

  test "retries using the ZuoraRateLimitHandler for too many requests error" do
    ::Billing::DisableAccountsWithUncollectableInvoices
      .expects(:perform)
      .raises(Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }))
    Failbot.expects(:report).never

    assert_enqueued_jobs(1, only: ::Billing::PositiveInvoiceCatchupDisableJob) do
      ::Billing::PositiveInvoiceCatchupDisableJob.perform_now(zuora_account_id: @customer.zuora_account_id, invoice_amount: "10.00")
    end

    assert_dogstats_increment 1, "billing.zuora_rate_limit_error", tags: ["class:billing/positive_invoice_catchup_disable_job"]
  end
end if GitHub.billing_enabled?
