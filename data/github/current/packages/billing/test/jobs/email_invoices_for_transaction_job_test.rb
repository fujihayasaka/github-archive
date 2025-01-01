# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class EmailInvoicesForTransactionJobTest < GitHub::TestCase
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

    @emails = [@paying_user.billing_email]
    @joined_emails = @emails.join(",")
  end

  setup do
    @invoice1 = create(:zuora_invoice, amount: 100, invoiceNumber: "INV-1")
    @invoice2 = create(:zuora_invoice, amount: 200, invoiceNumber: "INV-2")
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: EmailInvoicesForTransactionJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: EmailInvoicesForTransactionJob
  end

  test "does not send invoice by email if user associated to the transaction doesn't exist" do
    Billing::Zuora::Invoice.expects(:invoices_for_transaction).never
    assert_enqueued_jobs(0, only: EmailInvoiceJob) do
      EmailInvoicesForTransactionJob.perform_now(transaction_id: @dead_user_transaction.id, emails: @emails)
    end
  end

  test "does not send invoice by email if the transaction doesn't exist" do
    Billing::Zuora::Invoice.expects(:invoices_for_transaction).never
    assert_enqueued_jobs(0, only: EmailInvoiceJob) do
      EmailInvoicesForTransactionJob.perform_now(transaction_id: 0, emails: @emails)
    end
  end

  test "does not send invoice by email if there are no invoices associated to the transaction" do
    Billing::Zuora::Invoice.stubs(:invoices_for_transaction).returns([])
    assert_enqueued_jobs(0, only: EmailInvoiceJob) do
      EmailInvoicesForTransactionJob.perform_now(transaction_id: @paying_user_transaction.id, emails: @emails)
    end
  end

  test "enqueues the job EmailInvoiceJob when there are invoices associated to the transaction" do
    Billing::Zuora::Invoice.stubs(:invoices_for_transaction).returns([@invoice1, @invoice2])
    assert_enqueued_with(job: EmailInvoiceJob, args: [{ invoice_id: @invoice1.invoice_id, emails: @joined_emails }]) do
      assert_enqueued_with(job: EmailInvoiceJob, args: [{ invoice_id: @invoice2.invoice_id, emails: @joined_emails }]) do
        EmailInvoicesForTransactionJob.perform_now(transaction_id: @paying_user_transaction.id, emails: @emails)
      end
    end
  end

  test "calls Zuora's api to send the invoice by email when multiple emails are present" do
    multiple_emails = ["a@a.a", "b@b.b"]
    Billing::Zuora::Invoice.stubs(:invoices_for_transaction).returns([@invoice1])
    assert_enqueued_with(job: EmailInvoiceJob, args: [{ invoice_id: @invoice1.invoice_id, emails: multiple_emails.join(",") }]) do
      EmailInvoicesForTransactionJob.perform_now(transaction_id: @paying_user_transaction.id, emails: multiple_emails)
    end
  end

end if GitHub.billing_enabled?
