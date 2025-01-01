# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ScheduledAzureSupportPlanSyncJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  setup do
    GitHub.stubs(:braavos_support_entitlement_url).returns("http://braavos.test")
    GitHub.stubs(:braavos_support_entitlement_hmac).returns("nevermind")
    stub_domain("braavos.test")
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: ScheduledAzureSupportPlanSyncJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: ScheduledAzureSupportPlanSyncJob
  end

  test "runs in the support_plan_entitlement queue" do
    assert_enqueued_jobs(1, queue: :support_plan_entitlement) do
      ScheduledAzureSupportPlanSyncJob.perform_later
    end
  end

  test "sets the appropriate support plan on an Enterprise Account" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)

    service_offering_id_to_premium_plan = {
      1001 => "premium_premier",
      1158 => "premium_premier_asfp",
      1044 => "premium_premier_psfp",
      1133 => "premium_unified",
    }

    service_offering_id_to_premium_plan.each do |service_offering_id, premium_plan|
      SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: service_offering_id }] })

      Business.any_instance.expects(:update).with(microsoft_support_plan: premium_plan).once

      assert_nothing_raised do
        ScheduledAzureSupportPlanSyncJob.perform_now
      end
    end
  end

  test "sets the appropriate support plan when there are more than one packages" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)

    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1001 }, { uniqueID: 5678, serviceOfferingId: 1133 }] })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_equal "premium_unified", customer.business.microsoft_support_plan
  end

  test "logs when microsoft_support_plan is updated" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1133 }] })

    expected_keys = {
      "SeverityText": "INFO",
      "Body": "Updated Microsoft Support Plan for Enterprise",
      "fn": "ScheduledAzureSupportPlanSyncJob.update_microsoft_support_plan",
      "business_id": customer.business.id,
      "plan": "premium_unified"
    }

    assert_nothing_raised do
      assert_logged(**expected_keys) do
        ScheduledAzureSupportPlanSyncJob.perform_now
      end
    end
  end

  test "does not set the support plan if it is already set to the same" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer, microsoft_support_plan: "premium_unified")
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1133 }] })

    Business.any_instance.expects(:update).never

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "does not set the support plan if unknown serviceOfferingId" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1 }] })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_nil customer.business.microsoft_support_plan
  end

  test "logs when an unknown serviceOfferingId is returned" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1 }] })

    expected_keys = {
      "SeverityText": "ERROR",
      "Body": "Braavos returned an unknown Microsoft Support plan service offering id",
      "fn": "ScheduledAzureSupportPlanSyncJob.process_batch",
      "business_id": customer.business.id,
      "service_offering_ids": [1]
    }

    assert_nothing_raised do
      assert_logged(**expected_keys) do
        ScheduledAzureSupportPlanSyncJob.perform_now
      end
    end
  end

  test "does not set the support plan if the Azure Subscription is not active" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Closed Contract" })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_nil customer.business.microsoft_support_plan
  end

  test "removes the support plan if it is already set and no longer active" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer, microsoft_support_plan: "premium_unified")
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Closed Contract", type: "Premier", isRevoked: true })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_nil customer.business.microsoft_support_plan
  end

  test "does not remove the support plan unless isRevoked is set to true" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer, microsoft_support_plan: "premium_unified")
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Closed Contract", type: "Premier", isRevoked: false })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_equal "premium_unified", customer.business.microsoft_support_plan
  end

  test "does not set the support plan if isRevoked is true" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", isRevoked: true })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_nil customer.business.microsoft_support_plan
  end

  test "rescues from Configurable::MicrosoftSupportPlan::InvalidMicrosoftSupportPlan" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1001 }] })
    Business.any_instance.stubs(:update).raises(Configurable::MicrosoftSupportPlan::InvalidMicrosoftSupportPlan, "premium_invalid support plan")
    expected_keys = {
      "SeverityText": "ERROR",
      "exception.type": "Configurable::MicrosoftSupportPlan::InvalidMicrosoftSupportPlan",
      "exception.message": "premium_invalid support plan",
      "Body": "Error setting Microsoft Support Plan for Enterprise",
      "fn": "ScheduledAzureSupportPlanSyncJob.process_batch",
      "business_id": customer.business.id,
    }
    assert_nothing_raised do
      assert_logged(**expected_keys) do
        ScheduledAzureSupportPlanSyncJob.perform_now
      end
    end
  end

  test "reports when Braavos returns an unexpected type" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Invalid Support Plan" })
    expected_keys = {
      "SeverityText": "ERROR",
      "Body": "Braavos returned an unknown Microsoft Support Plan type",
      "fn": "ScheduledAzureSupportPlanSyncJob.process_batch",
      "business_id": customer.business.id,
      "type": "Invalid Support Plan"
    }
    assert_nothing_raised do
      assert_logged(**expected_keys) do
        ScheduledAzureSupportPlanSyncJob.perform_now
      end
    end
  end

  test "rescues from SupportEntitlement::Braavos::Client::ApiError" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).raises(SupportEntitlement::Braavos::Client::ApiError, "API error")

    expected_keys = {
      "SeverityText": "ERROR",
      "exception.type": "SupportEntitlement::Braavos::Client::ApiError",
      "exception.message": "API error",
      "Body": "Error setting Microsoft Support Plan for Enterprise",
      "fn": "ScheduledAzureSupportPlanSyncJob.process_batch",
      "business_id": customer.business.id,
    }
    assert_nothing_raised do
      assert_logged(**expected_keys) do
        ScheduledAzureSupportPlanSyncJob.perform_now
      end
    end
  end

  test "logs info when fetching the next batch of enterprises" do
    expected_keys = {
      "SeverityText": "INFO",
      "Body": "Fetching the next batch of enterprises",
      "fn": "ScheduledAzureSupportPlanSyncJob.next_batch",
      "offset_item_id": 0
    }
    assert_logged(**expected_keys) do
      ScheduledAzureSupportPlanSyncJob.new.next_batch
    end
  end

  test "handles a nil Business" do
    customer = create(:customer, :metered_ghe, :azure)
    SupportEntitlement::Braavos::Client.expects(:check_entitlement).never

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "ignores customers without an Azure Subscription ID" do
    customer = create(:customer, :metered_ghe)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.expects(:check_entitlement).never

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "ignores customers without metered GHE" do
    customer = create(:customer, bill_cycle_day: 1, metered_ghe: false)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.expects(:check_entitlement).never

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "does not set the support plan if its already set" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer, microsoft_support_plan: "premium_unified")
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier" })

    ScheduledAzureSupportPlanSyncJob.any_instance.expects(:update_microsoft_support_plan).never

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "increments scheduled_azure_support_plan_sync_job.microsoft_support_plan_updated when the support plan is updated" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1133 }] })

    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:increment).once.with("scheduled_azure_support_plan_sync_job.microsoft_support_plan_updated", tags: ["plan:premium_unified"])

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "increments scheduled_azure_support_plan_sync_job.microsoft_support_plan_updated when the support plan is cleared" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer, microsoft_support_plan: "premium_unified")
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Closed Contract", type: "Premier", isRevoked: true })

    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:increment).once.with("scheduled_azure_support_plan_sync_job.microsoft_support_plan_updated", tags: ["plan:standard"])

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "increments scheduled_azure_support_plan_sync_job.unknown_microsoft_support_plan_type when unknown support plan type is returned" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Unknown plan" })

    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:increment).once.with("scheduled_azure_support_plan_sync_job.unknown_microsoft_support_plan_type", tags: ["plan_type:Unknown plan"])

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "increments scheduled_azure_support_plan_sync_job.unknown_microsoft_support_plan_service_offering_id when unknown service offering id is returned" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1 }] })

    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:increment).once.with("scheduled_azure_support_plan_sync_job.unknown_microsoft_support_plan_service_offering_id")

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "increments scheduled_azure_support_plan_sync_job.error when InvalidMicrosoftSupportPlan error occurs" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ condition: "Active Contract", type: "Premier", packages: [{ uniqueID: 1234, serviceOfferingId: 1001 }] })
    Business.any_instance.stubs(:update).raises(Configurable::MicrosoftSupportPlan::InvalidMicrosoftSupportPlan, "premium_invalid support plan")

    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:increment).with("scheduled_azure_support_plan_sync_job.error", tags: ["error:Configurable::MicrosoftSupportPlan::InvalidMicrosoftSupportPlan"])

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "increments scheduled_azure_support_plan_sync_job.error when ApiError occurs" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer)
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).raises(SupportEntitlement::Braavos::Client::ApiError, "API error")

    GitHub.dogstats.expects(:increment).at_least_once
    GitHub.dogstats.expects(:increment).with("scheduled_azure_support_plan_sync_job.error", tags: ["error:SupportEntitlement::Braavos::Client::ApiError"])

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end
  end

  test "removes microsoft_support_plan when the subscription is not found" do
    customer = create(:customer, :metered_ghe, :azure)
    business = create(:business, customer: customer, microsoft_support_plan: "premium_unified")
    SupportEntitlement::Braavos::Client.stubs(:check_entitlement).returns({ not_found: true })

    assert_nothing_raised do
      ScheduledAzureSupportPlanSyncJob.perform_now
    end

    assert_nil customer.business.microsoft_support_plan
  end
end
