# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::ProcessBusinessLicenseConsumptionExportJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @business = create(:business)
    @actor = @business.admins.first
    @export = Business::LicenseConsumptionExport.create(business: @business, actor: @actor)
  end

  setup do
    s3_client = Aws::S3::Client.new(stub_responses: true)
    GitHub.stubs(:s3_license_consumption_client).returns(s3_client)
  end

  test "updates a corresponding job status" do
    Business::LicenseCsvGenerator.any_instance.stubs(:generate).returns("foo,bar")
    Licensing::ProcessBusinessLicenseConsumptionExportJob.perform_now(@export.id)
    status = JobStatus.find(@export.token)
    assert_predicate status, :success?
  end

  test "retries on recoverable exceptions" do
    assert_retry_conditions job: Licensing::ProcessBusinessLicenseConsumptionExportJob, args: [@export.id]
  end

  test "Calls s3 to remove remote file" do
    Business::LicenseConsumptionExport.any_instance.expects(:remote_object).at_least_once.returns(stub(delete: true))
    @export.destroy!
  end

  test "Does not call s3 to remove remote file on proxima" do
    GitHub.stubs(:multi_tenant_enterprise?).returns(true)
    Business::LicenseConsumptionExport.any_instance.expects(:remote_object).never
    @export.destroy!
  end

  test "sends email when business size exceeds threshold" do
    BusinessMailer.expects(:enterprise_cloud_licensing_report)
      .once
      .returns(stub(deliver_later: true))

    users = create_list(:user, 3)
    perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { @business.add_user_accounts(users.pluck(:id)) }

    Business::LicenseConsumptionExport.stub_const(:LICENSE_CONSUMPTION_REPORT_EMAIL_USER_COUNT, 1) do
      @export.process
      assert @export.is_notified?
    end
  end unless GitHub.single_business_environment?

  test "does not send email when business size is below threshold" do
    BusinessMailer.expects(:enterprise_cloud_licensing_report).never

    users = create_list(:user, 3)
    perform_enqueued_jobs(only: [BusinessUserAccountCreateForOrganizationJob]) { @business.add_user_accounts(users.pluck(:id)) }

    Business::LicenseConsumptionExport.stub_const(:LICENSE_CONSUMPTION_REPORT_EMAIL_USER_COUNT, 100) do
      @export.process
      refute @export.is_notified?
    end
  end
end
