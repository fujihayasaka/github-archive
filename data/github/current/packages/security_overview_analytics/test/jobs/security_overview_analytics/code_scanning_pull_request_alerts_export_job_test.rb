# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlertsExportJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper
    include SecurityCenter::TestFixtures
    include ::SecurityOverviewAnalytics::TestFixtures

    fixtures do
      create_business_level_fixtures

      [
        @org1_private_repo = create(:private_repository, owner: @org),
        @org1_public_repo = create(:public_repository, owner: @org),
        @org2_private_repo = create(:private_repository, owner: @org2),
        @org2_public_repo = create(:public_repository, owner: @org2),
      ].each do |repository|
        create_pull_request_alerts(repository:, base_date_id: 20240801)
      end
    end

    setup do
      @default_end_date = ::Date.parse("2024-08-14")
      @default_start_date = @default_end_date - 30.days

      # Mock the abstract blob store
      @blob_store = mock("::SecurityCenter::Export::BlobStorageService")
      @blob_store.stubs(:create)
      @blob_store.stubs(:store)
      ::SecurityCenter::Export::BlobStorageService.stubs(:get).returns(@blob_store)

      # Clear jobs and email cache
      reset_jobs
      ActionMailer::Base.deliveries.clear
    end

    context ".enqueue_for_business" do
      test "it validates required parameters" do
        kwargs = {
          scope: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: "foo"
        }

        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, scope: nil) }
        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, organizations: nil) }
        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, user: nil) }
        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, export_id: nil) }
      end

      test "it updates job status on completion" do
        token = export_token(scope: @business)
        create_job_status(id: token, scope: @business)

        CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
          business: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: token
        )

        assert ::SecurityCenter::Export::JobStatus.find(token)&.pending?

        perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob

        assert ::SecurityCenter::Export::JobStatus.find(token)&.finished?
        assert ::SecurityCenter::Export::JobStatus.find(token)&.success?
      end

      test "it updates ttl after enqueue" do
        Timecop.freeze do
          token = export_token(scope: @business)
          create_job_status(id: token, scope: @business)
          assert_equal 1.minute.to_i, ::SecurityCenter::Export::JobStatus.find(token)&.ttl

          CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
            business: @business,
            organizations: @business.organizations.to_a,
            user: @orgs_owner,
            export_id: token
          )

          assert ::SecurityCenter::Export::JobStatus.find(token)&.pending?

          perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob

          assert_equal 10.minutes, ::SecurityCenter::Export::JobStatus.find(token)&.ttl
        end
      end

      test "it sends email on completion" do
        token = export_token(scope: @business)
        create_job_status(id: token, scope: @business)

        CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
          business: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: token
        )

        assert_equal 0, ActionMailer::Base.deliveries.size

        perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, @orgs_owner.email
        assert_includes email.subject, "[GitHub] Your CodeQL pull request alerts CSV is ready"
      end
    end

    context ".enqueue_for_organization" do
      test "it validates required parameters" do
        kwargs = {
          scope: @org,
          allowed_repo_ids: nil, # optional
          user: @orgs_owner,
          user_session: @orgs_owner_user_session,
          export_id: "foo"
        }

        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, scope: nil) }
        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, user: nil) }
        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, user_session: nil) }
        assert_raises(ArgumentError) { CodeScanningPullRequestAlertsExportJob.perform_later(**kwargs, export_id: nil) }
      end

      test "it updates job status on completion" do
        token = export_token(scope: @org)
        create_job_status(id: token, scope: @org)

        CodeScanningPullRequestAlertsExportJob.enqueue_for_organization(
          organization: @org,
          allowed_repo_ids: nil,
          user: @orgs_owner,
          user_session: @orgs_owner_user_session,
          export_id: token
        )

        assert ::SecurityCenter::Export::JobStatus.find(token)&.pending?

        perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob

        assert ::SecurityCenter::Export::JobStatus.find(token)&.finished?
        assert ::SecurityCenter::Export::JobStatus.find(token)&.success?
      end

      test "it updates ttl after enqueue" do
        Timecop.freeze do
          token = export_token(scope: @org)
          create_job_status(id: token, scope: @org)
          assert_equal 1.minute.to_i, ::SecurityCenter::Export::JobStatus.find(token)&.ttl

          CodeScanningPullRequestAlertsExportJob.enqueue_for_organization(
            organization: @org,
            allowed_repo_ids: nil,
            user: @orgs_owner,
            user_session: @orgs_owner_user_session,
            export_id: token
          )

          assert ::SecurityCenter::Export::JobStatus.find(token)&.pending?

          perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob

          assert_equal 10.minutes, ::SecurityCenter::Export::JobStatus.find(token)&.ttl
        end
      end

      test "it sends email on completion" do
        token = export_token(scope: @org)
        create_job_status(id: token, scope: @org)

        CodeScanningPullRequestAlertsExportJob.enqueue_for_organization(
          organization: @org,
          allowed_repo_ids: nil,
          user: @orgs_owner,
          user_session: @orgs_owner_user_session,
          export_id: token
        )

        assert_equal 0, ActionMailer::Base.deliveries.size

        perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, @orgs_owner.email
        assert_includes email.subject, "[GitHub] Your CodeQL pull request alerts CSV is ready"
      end
    end

    context "error handling" do
      test "it updates job status on error" do
        token = export_token(scope: @business)
        create_job_status(id: token, scope: @business)

        CodeScanningPullRequestAlertsExportJob::DataExportQuery.any_instance
          .expects(:perform).raises(StandardError, "boom")

        CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
          business: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: token
        )

        assert_raises do
          perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob
        end

        job_status = ::SecurityCenter::Export::JobStatus.find(token)
        refute_nil job_status
        assert job_status&.finished?
        assert job_status&.error?

        assert_dogstats_increment(1, "security_center.export.error")
      end

      test "it sends an email on error" do
        token = export_token(scope: @business)
        create_job_status(id: token, scope: @business)

        CodeScanningPullRequestAlertsExportJob::DataExportQuery.any_instance
          .expects(:perform).raises(StandardError, "boom")

        CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
          business: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: token
        )

        assert_raises do
          perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob
        end

        assert_equal 1, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, @orgs_owner.email
        assert_includes email.subject, "[GitHub] Sorry, your CodeQL pull request alerts CSV couldn't be generated"

        assert_dogstats_increment(1, "security_center.export.error")
      end

      test "it reports mailing errors, but still updates job status as success" do
        token = export_token(scope: @business)
        create_job_status(id: token, scope: @business)

        SecurityCenterMailer.any_instance
          .expects(:csv_export_ready).raises(StandardError, "boom")

        CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
          business: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: token
        )

        assert_nothing_raised do
          perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob
        end

        assert ::SecurityCenter::Export::JobStatus.find(token)&.finished?
        assert ::SecurityCenter::Export::JobStatus.find(token)&.success?

        assert_dogstats_increment(1, "security_center.export.error")
      end

      test "Logs telemetry and raises error when status is not found" do
        CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
          business: @business,
          organizations: @business.organizations.to_a,
          user: @orgs_owner,
          export_id: "foo"
        )

        assert_raises(StandardError) do
          perform_enqueued_jobs only: CodeScanningPullRequestAlertsExportJob
        end

        assert_dogstats_increment(1, "security_center.code_scanning_pull_request_alerts_export_batched_job.job_status_not_found")
      end
    end

    context "batch job" do
      test "queues subsequent jobs for batching" do
        token = export_token(scope: @business)
        create_job_status(id: token, scope: @business)

        batch_size = 100
        expected_batch_count = 5

        @blob_store.expects(:create).once
        @blob_store.expects(:store).times(expected_batch_count)

        CodeScanningPullRequestAlertsExportJob::DataExportQuery.stub_const(:PAGE_SIZE, batch_size) do
          assert_performed_jobs(expected_batch_count, only: CodeScanningPullRequestAlertsExportJob) do
            perform_enqueued_jobs(only: CodeScanningPullRequestAlertsExportJob) do
              CodeScanningPullRequestAlertsExportJob.enqueue_for_business(
                business: @business,
                organizations: @business.organizations.to_a,
                user: @orgs_owner,
                export_id: token
              )
            end
          end
        end
      end
    end

    private

    def export_token(kwargs = {})
      ::SecurityCenter::Export::TokenGenerator.create_token(
        **T.unsafe({
          scope: @business,
          user: @orgs_owner,
          query: "",
          start_date: @default_start_date,
          end_date: @default_end_date,
          feature_type: CodeScanningPullRequestAlertsExportJob::FEATURE_TYPE,
          requested_at: @default_end_date.to_time,
          **kwargs
        }),
      )
    end

    sig { params(id: String, scope: T.any(Business, Organization), query: String, requester: User, requested_at: Time, start_date: Time, end_date: Time).returns(::SecurityCenter::Export::JobStatus) }
    def create_job_status(
      id:,
      scope:,
      query: "",
      requester: @orgs_owner,
      requested_at: @default_end_date.to_time,
      start_date: @default_start_date,
      end_date: @default_end_date
    )
      ::SecurityCenter::Export::JobStatus.create(id:, query:, scope:, requester:, requested_at:, start_date:, end_date:)
    end
  end
end
