# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class CoverageExportJobTest < GitHub::TestCase
    extend T::Sig

    include JobTestHelper
    include DogstatsTestHelpers

    fixtures do
      @owner = create(:user)
      @org = create(:organization, admin: @owner)
    end

    setup do
      @requested_at = Time.now
    end

    context "enterprise", enterprise_only: true do
      test "JobStatus marked as success" do
        export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
        Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

        queue_job(requested_at: @requested_at)

        assert Export::JobStatus.find(export_id)&.pending?

        perform_enqueued_jobs(only: [CoverageExportJob])

        assert Export::JobStatus.find(export_id)&.finished?
        assert Export::JobStatus.find(export_id)&.success?
      end
    end

    context "dotcom", skip_enterprise: true do
      context "Dirty exit" do
        test "Retries" do
          assert_retry_on_dirty_exit job: CoverageExportJob, args: [scope: @org, user: @owner, query_string: ""], using_kwargs: true
        end

        test "Doesn't set JobStatus to error!" do
          Coverage::ExportDataQuery.any_instance.stubs(:query_data).raises(Aqueduct::Worker::JobKilled, "whoops!")
          Export::JobStatus.any_instance.expects(:error!).never

          export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
          Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

          queue_job(requested_at: @requested_at)
          assert_enqueued_with(job: CoverageExportJob, args: [scope: @org, user: @owner, query_string: "", requested_at:  @requested_at]) do
            perform_enqueued_jobs only: [CoverageExportJob]
          end
        end
      end

      test "Logs telemetry when status is not found" do
        queue_job(requested_at: Time.now)
        perform_enqueued_jobs only: [CoverageExportJob]
        assert_dogstats_increment(1, "security_center.coverage_export_job.job_status_not_found")
      end

      test "Queries data, serializes it, and puts it into blob storage" do
        export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
        Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

        Coverage::ExportDataQuery.any_instance.expects(:query_data).returns([{ my: "data" }])
        Coverage::ExportCsvGenerator.expects(:generate).with([{ my: "data" }]).returns("my\ndata")

        service = Export::BlobStorageService.get(@org)
        service.expects(:store).with(export_id, "my\ndata", "coverage")
        Export::BlobStorageService.expects(:get).returns(service)

        queue_job(requested_at: @requested_at)
        perform_enqueued_jobs(only: [CoverageExportJob])
      end

      context "Allowed repositories" do
        test "Passes return value of AuthorizationEnumerator#allowed_repository_ids_for_organization_member to 'allowed_repository_ids_by_feature'" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
          Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

          adminable_repo_ids = [[1, 5, 8], false]

          AuthorizationEnumerator.any_instance.expects(:adminable_repo_ids).returns(adminable_repo_ids)

          data_query_stub = stub
          data_query_stub.expects(:query_data).returns([])
          Coverage::ExportDataQuery.expects(:new).with(has_entries(
            allowed_repository_ids: adminable_repo_ids.first
          )).returns(data_query_stub)

          queue_job(requested_at: @requested_at)
          perform_enqueued_jobs(only: [CoverageExportJob])
        end
      end

      context "JobStatus" do
        test "Marked as success when job finishes" do
          SecurityCenter::Export::AzureBlobStorageService.any_instance.expects(:store).once

          export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
          Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

          queue_job(requested_at: @requested_at)

          assert Export::JobStatus.find(export_id)&.pending?

          perform_enqueued_jobs(only: [CoverageExportJob])

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.success?
        end

        test "Marked as failed when job raises an error" do
          export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
          Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

          Export::BlobStorageService.expects(:get).raises(StandardError.new("Something went wrong"))

          queue_job(requested_at: @requested_at)

          assert Export::JobStatus.find(export_id)&.pending?

          assert_raises(StandardError) do
            perform_enqueued_jobs(only: [CoverageExportJob])
          end

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.error?
          assert_equal "We couldn't generate your report. Please try again later. If the problem persists, please contact support.", Export::JobStatus.find(export_id)&.error_message
        end

        test "Marked as failed and use given error message when job raises an DataLimitExceededError" do
          export_id = create_export_id(user: @owner, org: @org, requested_at: @requested_at)
          Export::JobStatus.create(id: export_id, query: "", requested_at: @requested_at)

          queue_job(requested_at: @requested_at)

          assert Export::JobStatus.find(export_id)&.pending?

          SecurityCenter::Coverage::ExportDataQuery
            .any_instance
            .stubs(:query_data)
            .raises(SecurityCenter::Export::DataQuery::DataLimitExceededError.new("Your query exceeds the maximum number of repositories."))

          perform_enqueued_jobs(only: [CoverageExportJob])

          assert_dogstats_increment(1, "security_center.export.data_limit_exceeded", tags: ["scope:organization", "feature:coverage"])

          assert Export::JobStatus.find(export_id)&.finished?
          assert Export::JobStatus.find(export_id)&.error?
          assert Export::JobStatus.find(export_id)&.error_message.starts_with?("Your query exceeds the maximum number of repositories.")
        end
      end
    end

    private

    sig do
      params(
        requested_at: Time,
        scope: Organization,
        user: User,
        query_string: String,
      ).returns(CoverageExportJob)
    end
    def queue_job(requested_at:, scope: @org, user: @owner, query_string: "")
      CoverageExportJob.perform_later(scope:, user:, query_string:, requested_at:).tap do |job|
        fail "Expected job to be enqueued" unless job
      end
    end

    sig { params(requested_at: Time, user: User, org: Organization, query: String).returns(String) }
    def create_export_id(requested_at:, user:, org:, query: "")
      Export::TokenGenerator.create_token(user:, scope: org, query:, feature_type: "coverage", requested_at:)
    end
  end
end
