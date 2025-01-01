# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::MeteredReportExportJobTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper

  setup do
    @s3_client = Aws::S3::Client.new(stub_responses: true)
    @resource_mock = mock("Aws::S3::Resource")
    Aws::S3::Resource.stubs(:new).returns(@resource_mock)

    GitHub.stubs(:s3_metered_exports_client).returns(@s3_client)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "uploads the CSV and sends user an email to CSV" do
    travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
      requester = create(:user)
      org = create(:organization)
      repo  = create(:repository, owner: org)

      codespace_workflow = create(:workflow, repository: repo,
        name: Codespaces::Prebuilds::WORKFLOW_NAME,
        path: "dynamic/#{Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME}/#{Codespaces::Prebuilds::WORKFLOW_SLUG}")

      mock_get_usage_line_items_response_without_usage
      mock_get_usage_line_items_response_with(usage_line_items: [
        create_mock_usage_line_item(
          repository_id: repo.id,
          quantity: 1,
          product_sku_name: "linux",
          multiplier: 1,
          rate_plan_unit_price: 0.008,
          usage_at: Google::Protobuf::Timestamp.new(seconds: 9.days.ago.to_i),
          custom_fields: {
            "actions.workflow.id": codespace_workflow.id.to_s,
          },
        ),
      ], times: 1, required_params: { product_name: Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:actions] })

      @resource_mock.expects(:bucket).with("github-billing-report-exports").returns(@resource_mock).at_least_once
      @resource_mock.expects(:object).with do |arg|
        arg =~ /Organization\/#{org.name.underscore}\/[A-Za-z0-9]{8}_2019-11-20_7.csv/
      end.returns(@resource_mock).at_least_once

      @resource_mock.expects(:put).with(has_entries(body: instance_of(String), content_type: "text/csv")).at_least_once

      start_date = 7.days.ago.beginning_of_day.to_datetime
      end_date = Time.zone.now.beginning_of_day.to_datetime
      assert_difference -> { ActionMailer::Base.deliveries.count } => 1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          Billing::MeteredReportExportJob.perform_now(requester, org, 7, start_date: start_date, end_date: end_date)
        end
      end

      email = ActionMailer::Base.deliveries.last
      assert_equal [requester.email], email.to
      assert_includes email.subject, "Your usage report is ready"
      assert_match "Your usage report for #{org.name} is ready", email.body.to_json
      assert_match start_date.strftime("%D"), email.body.to_json
      assert_match end_date.strftime("%D"), email.body.to_json

      assert_dogstats_increment(1, "billing.metered_report_export_job.success",
        tags: ["days:7", "staff:false"]
      )
    end
  end

  test "sends error email when creating export fails" do
    requester = create(:user)
    org = create(:organization)

    Billing::MeteredUsageReportGenerator.expects(:csv_for).raises(StandardError)
    mailer_mock = mock(deliver_later: nil)
    Billing::ReportMailer.expects(:metered_export_error).returns(mailer_mock)

    assert_raises StandardError do
      Billing::MeteredReportExportJob.perform_now(requester, org, 7)
    end

    assert_dogstats_increment(1, "billing.metered_report_export_job.error",
      tags: ["billable_owner_id:#{org.id}", "billable_owner_type:organization", "days:7", "staff:false"]
    )
  end

  test "locks job based on owner days" do
    travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
      requester = create(:user)
      business = create(:business)
      org = create(:organization, business: business)

      GitHub::Restraint.any_instance.expects(:lock!).with("metered-export-business-#{business.id}-7", 1, 5.minutes)

      Billing::MeteredReportExportJob.perform_now(requester, business, 7)
    end
  end

  test "discards the job on GitHub::Restraint::UnableToLock errors" do
    travel_to Time.zone.local(2019, 11, 20, 10, 0, 0) do
      requester = create(:user)
      business = create(:business)

      GitHub::Restraint.any_instance.expects(:lock!).with("metered-export-business-#{business.id}-7", 1, 5.minutes).raises(GitHub::Restraint::UnableToLock)

      Billing::MeteredReportExportJob.perform_now(requester, business, 7)
    end
  end
end if GitHub.billing_enabled?
