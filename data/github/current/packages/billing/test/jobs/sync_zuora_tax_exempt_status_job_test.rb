# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncZuoraTaxExemptStatusJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
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

    assert_logged(Body: "Tax exemption status not found") do
      SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: 0)
    end
  end

  test "logs an error when updating the tax exempt status fails" do
    disable_feature_flag(:billing_validate_zuora_tax_exempt_status)
    tax_exemption_status = create(:tax_exemption_status, customer: @customer)
    GitHub.zuorest_client.class.any_instance.expects(:update_account)
      .with(
        @customer.zuora_account_id,
        { taxInfo: { exemptStatus: "Yes", exemptCertificateId: tax_exemption_status.id.to_s } },
        { "Content-Type" => "application/json" }
      )
      .returns({ "success" => false })
      .once

    assert tax_exemption_status.approved?

    assert_logged(Body: "Failed to update tax exempt status in Zuora") do
      SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
    end
  end

  test "syncs the tax exempt status 'Yes' to Zuora" do
    disable_feature_flag(:billing_validate_zuora_tax_exempt_status)
    tax_exemption_status = create(:tax_exemption_status, customer: @customer)
    GitHub.zuorest_client.class.any_instance.expects(:update_account)
      .with(
        @customer.zuora_account_id,
        { taxInfo: { exemptStatus: "Yes", exemptCertificateId: tax_exemption_status.id.to_s } },
        { "Content-Type" => "application/json" }
      )
      .returns({ "success" => true })
      .once

    assert tax_exemption_status.approved?

    assert_logged(Body: "Updated tax exempt status in Zuora") do
      SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
    end
  end

  test "syncs the tax exempt status 'No' to Zuora" do
    disable_feature_flag(:billing_validate_zuora_tax_exempt_status)
    tax_exemption_status = create(:tax_exemption_status, customer: @customer, status: :rejected, status_reason: "Some reason")
    GitHub.zuorest_client.class.any_instance.expects(:update_account)
      .with(
        @customer.zuora_account_id,
        { taxInfo: { exemptStatus: "No", exemptCertificateId: tax_exemption_status.id.to_s } },
        { "Content-Type" => "application/json" }
      )
      .returns({ "success" => true })
      .once

    assert tax_exemption_status.rejected?

    assert_logged(Body: "Updated tax exempt status in Zuora") do
      SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
    end
  end

  context "FF billing_validate_zuora_tax_exempt_status" do
    test "logs an error when the validation fails" do
      enable_feature_flag(:billing_validate_zuora_tax_exempt_status)
      tax_exemption_status = create(:tax_exemption_status, customer: @customer)
      GitHub.zuorest_client.class.any_instance.expects(:update_account)
        .with(
          @customer.zuora_account_id,
          { taxInfo: { exemptStatus: "Yes", exemptCertificateId: tax_exemption_status.id.to_s } },
          { "Content-Type" => "application/json" }
        )
        .returns({ "success" => true })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:get_account)
        .with(@customer.zuora_account_id)
        .returns({})
        .once

      assert tax_exemption_status.approved?

      assert_logged(Body: "Failed to validate tax exempt status in Zuora") do
        SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
      end
    end

    test "logs an error when the tax exempt status was not updated" do
      enable_feature_flag(:billing_validate_zuora_tax_exempt_status)
      tax_exemption_status = create(:tax_exemption_status, customer: @customer)
      GitHub.zuorest_client.class.any_instance.expects(:update_account)
        .with(
          @customer.zuora_account_id,
          { taxInfo: { exemptStatus: "Yes", exemptCertificateId: tax_exemption_status.id.to_s } },
          { "Content-Type" => "application/json" }
        )
        .returns({ "success" => true })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:get_account)
        .with(@customer.zuora_account_id)
        .returns({ "TaxExemptStatus" => "No" })
        .once

      assert tax_exemption_status.approved?

      assert_logged(Body: "Incorrect tax exempt status in Zuora") do
        SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
      end
    end

    test "logs success when the tax exempt status was updated" do
      enable_feature_flag(:billing_validate_zuora_tax_exempt_status)
      tax_exemption_status = create(:tax_exemption_status, customer: @customer)
      GitHub.zuorest_client.class.any_instance.expects(:update_account)
        .with(
          @customer.zuora_account_id,
          { taxInfo: { exemptStatus: "Yes", exemptCertificateId: tax_exemption_status.id.to_s } },
          { "Content-Type" => "application/json" }
        )
        .returns({ "success" => true })
        .once

      GitHub.zuorest_client.class.any_instance.expects(:get_account)
        .with(@customer.zuora_account_id)
        .returns({ "TaxExemptStatus" => "Yes" })
        .once

      assert tax_exemption_status.approved?

      assert_logged(Body: "Validated tax exempt status in Zuora") do
        SyncZuoraTaxExemptStatusJob.perform_now(zuora_account_id: @customer.zuora_account_id, tax_exemption_status_id: T.must(tax_exemption_status.id))
      end
    end
  end
end if GitHub.billing_enabled?
