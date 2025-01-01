# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module Billing
  class CancelAuthorizationBillingTransactionJobTest < GitHub::TestCase
    include GitHub::ZuoraTestHelper
    include JobTestHelper
    include HydroTestHelpers

    fixtures do
      @user = create(:credit_card_user)
      @business = create(:business, :with_self_serve_payment)
    end

    setup do
      FakeZuora.mock
    end

    test "retries on dirty exit" do
      assert_retry_on_dirty_exit job: CancelAuthorizationBillingTransactionJob
    end

    test "retries on recoverable exceptions" do
      assert_retry_on_recoverable_exceptions job: CancelAuthorizationBillingTransactionJob
    end

    context "cancel paypal auths" do
      test "sets the status to :authorization_cancelled when transaction is voided successfully" do
        ::Braintree::Transaction.stubs(:void).returns(
          ::Braintree::SuccessfulResult.new({
            transaction: ::Braintree::Transaction._new(nil, {
              id: "fake-transaction-id",
              status: "voided",
              processor_response_code: "1000",
            })
          })
        )

        authorization = create(:billing_transaction, :authorization, :authorized, :business_owned, customer: @business.customer, platform: :braintree)

        perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
          Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: authorization.id)
        end

        assert_equal authorization.reload.last_status, "authorization_cancelled"
      end

      test "does not change the status when transaction is not voided successfully" do
        ::Braintree::Transaction.stubs(:void).returns(
          ::Braintree::ErrorResult.new(nil, {
            message: "Transaction can only be voided if status is authorized, submitted_for_settlement, or - for PayPal - settlement_pending.",
            errors: {
              errors: [{
                code: "91504",
                message: "Transaction can only be voided if status is authorized, submitted_for_settlement, or - for PayPal - settlement_pending."
              }],
            },
          })
        )

        authorization = create(:billing_transaction, :authorization, :authorized, :business_owned, customer: @business.customer, platform: :braintree)

        perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
          Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: authorization.id)
        end

        assert_equal authorization.reload.last_status, "authorized"
      end
    end

    context "cancel zuora auths" do
      test "Cancels a pending status update authorization" do
        authorization = create(:billing_transaction, :authorization, :authorized, user: @user)

        perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
          Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: authorization.id)
        end

        assert_equal authorization.reload.last_status, "authorization_cancelled"
      end

      test "Does not cancel a final status authorization" do
        failed_authorization = create(:billing_transaction, :authorization, :failed, user: @user)
        declined_authorization = create(:billing_transaction, :authorization, :processor_declined, user: @user)

        perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
          Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: failed_authorization.id)
          Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: declined_authorization.id)
        end

        assert_equal failed_authorization.reload.last_status, "failed"
        assert_equal declined_authorization.reload.last_status, "processor_declined"
      end

      test "publishes authorization cancelled hydro event" do
        authorization = create(:billing_transaction, :authorization, :authorized, user: @user)

        perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
          Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: authorization.id)
        end

        assert_hydro_messages count: 1, schema: "github.billing.v0.AuthorizationTransactionCancelled"
      end

      context "businesses" do
        test "Cancels a pending status update authorization for a business" do
          authorization = create(:billing_transaction, :authorization, :authorized, :business_owned, customer: @business.customer)

          perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
            Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: authorization.id)
          end

          assert_equal authorization.reload.last_status, "authorization_cancelled"
        end

        test "Does not cancel a final status authorization" do
          failed_authorization = create(:billing_transaction, :authorization, :business_owned, :failed, customer: @business.customer)
          declined_authorization = create(:billing_transaction, :authorization, :business_owned, :processor_declined, customer: @business.customer)

          perform_enqueued_jobs(only: Billing::CancelAuthorizationBillingTransactionJob) do
            Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: failed_authorization.id)
            Billing::CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: declined_authorization.id)
          end

          assert_equal failed_authorization.reload.last_status, "failed"
          assert_equal declined_authorization.reload.last_status, "processor_declined"
        end
      end
    end
  end
end if GitHub.billing_enabled?
