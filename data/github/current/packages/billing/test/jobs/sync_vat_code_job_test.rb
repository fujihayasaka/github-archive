# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncVatCodeJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper

  fixtures do
    @org = create(:organization, :with_corporate_terms, customer_account_factory: :credit_card_customer_account)
    @customer = @org.customer
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SyncVatCodeJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SyncVatCodeJob
  end

  test "updates Zuora with the given vat_code when a SyncVatCodeJob is executed" do
    vat_code = "12345"
    GitHub.zuorest_client.class.any_instance.expects(:update_account).with(
      @customer.zuora_account_id,
      { taxInfo: { VATId: vat_code } },
      { "Content-Type" => "application/json" }
    )
    .returns({ "success" => true })
    .once

    SyncVatCodeJob.perform_now(zuora_account_id: @customer.zuora_account_id, vat_code:)
  end

  test "sets Zuora's vat code to empty if a nil value is provided for vat_code" do
    GitHub.zuorest_client.class.any_instance.expects(:update_account).with(
      @customer.zuora_account_id,
      { taxInfo: { VATId: nil } },
      { "Content-Type" => "application/json" }
    )
    .returns({ "success" => true })
    .once

    SyncVatCodeJob.perform_now(zuora_account_id: @customer.zuora_account_id, vat_code: nil)
  end

  test "logs an error when updating the tax exempt status fails" do
    vat_code = "12345"
    GitHub.zuorest_client.class.any_instance.expects(:update_account)
      .with(
        @customer.zuora_account_id,
        { taxInfo: { VATId: vat_code } },
        { "Content-Type" => "application/json" }
      )
      .returns({ "success" => false })
      .once

    assert_logged(Body: "Failed to sync vat code with Zuora") do
      SyncVatCodeJob.perform_now(zuora_account_id: @customer.zuora_account_id, vat_code:)
    end
  end
end if GitHub.billing_enabled?
