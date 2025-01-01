# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncZuoraTaxExemptStatusJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization, :with_corporate_terms, customer_account_factory: :credit_card_customer_account)
    @customer = @org.customer
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SyncZuoraTaxExemptStatusJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SyncZuoraTaxExemptStatusJob
  end

  test "does not update Zuora if a TaxExemptionRecord doesn't exist" do
    GitHub.zuorest_client.class.any_instance.expects(:update_account).never

    SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: 0)
  end

  test "syncs the tax exempt status 'Yes' to Zuora" do
    GitHub.zuorest_client.class.any_instance.expects(:update_account)
      .with(
        @customer.zuora_account_id,
        { taxInfo: { exemptStatus: "Yes" } },
        { "Content-Type" => "application/json" }
      )
      .returns([{ success: true }])
      .once
    tax_exemption_status = create(:tax_exemption_status, customer: @customer)

    assert tax_exemption_status.approved?
    SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
  end

  test "syncs the tax exempt status 'No' to Zuora" do
    tax_exemption_status = create(:tax_exemption_status, customer: @customer, status: :rejected, status_reason: "Some reason")
    GitHub.zuorest_client.class.any_instance.expects(:update_account)
      .with(
        @customer.zuora_account_id,
        { taxInfo: { exemptStatus: "No" } },
        { "Content-Type" => "application/json" }
      )
      .returns([{ success: true }])
      .once

    assert tax_exemption_status.rejected?
    SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
  end
end if GitHub.billing_enabled?
