# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class EmailInvoiceJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @paying_user = create(:credit_card_user)
    @user = create(:user)
    @customer = create(:customer, zuora_account_id: "2c92c0f8511f4b9d01512680ab282370")
    @organization = create(:organization, admin: @user, customer: @customer)
    @self_serve_business = create(:business, :with_self_serve_payment, owners: [@user])

    @paying_user_transaction = create(:billing_transaction, user: @paying_user, transaction_id: "0000SUCCESS", last_status: :settled)
    @dead_user_transaction = create(:billing_transaction)
    @dead_user_transaction.user = nil
    @dead_user_transaction.save!

    @emails = [@paying_user.billing_email].join(",")
  end

  setup do
    @invoice1 = create(:zuora_invoice, amount: 100, invoiceNumber: "INV-1")
    @invoice2 = create(:zuora_invoice, amount: 200, invoiceNumber: "INV-2")
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: EmailInvoiceJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: EmailInvoiceJob
  end

  test "calls Zuora's api to send the invoice by email" do
    GitHub.zuorest_client.class.any_instance.expects(:email_invoice)
      .with(@invoice1.invoice_id, { emailAddresses: @emails }, { "Content-Type" => "application/json" })
      .returns({ "success" => true  })
      .once

    EmailInvoiceJob.perform_now(invoice_id: @invoice1.invoice_id, emails: @emails)
  end


  test "logs error and increments Datadog metric if an api call to send the invoice by email fails" do
    GitHub.zuorest_client.class.any_instance.expects(:email_invoice).returns({ "success" => false, "reasons" => [{ "message" => "something went wrong" }] })
    assert_logged(
      "code.namespace" => "EmailInvoiceJob",
      "gh.billing.zuora.invoice.ids" => @invoice1.invoice_id,
      "gh.billing.zuora.response.success" => false,
      "gh.billing.zuora.response.error_message" => "something went wrong",
    ) do
      EmailInvoiceJob.perform_now(invoice_id: @invoice1.invoice_id, emails: @emails)
    end
    assert_dogstats_increment(1, "billing.email_zuora_invoice_job.email_invoice_failure")
  end
end if GitHub.billing_enabled?
