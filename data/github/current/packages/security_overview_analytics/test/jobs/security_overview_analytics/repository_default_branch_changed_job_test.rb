# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class RepositoryDefaultBranchChangedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      @owner = create(:user)
      @org = create(:organization, admin: @owner)
      @repo = create(:repository, owner: @org)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(true)
    end

    context "#perform" do
      test "deletes all code scanning alert revisions for the repo" do
        date_id = ::SecurityOverviewAnalytics::Date.id_from_time(Time.current.utc)
        next_revision_date_id = Date::FUTURE_DATE_ID

        target_alert_count = 5.times do |i|
          create(:soa_code_scanning_alert_revision, repository: @repo, alert_number: i, date_id:, next_revision_date_id:)
        end

        other_repo = create(:repository, owner: @org)
        create(:soa_code_scanning_alert_revision, repository: other_repo, date_id:, next_revision_date_id:)

        other_org = create(:organization)
        other_org_repo = create(:repository, owner: other_org)
        create(:soa_code_scanning_alert_revision, repository: other_org_repo, date_id:, next_revision_date_id:)

        assert_difference("CodeScanningAlertRevision.count", -target_alert_count) do
          RepositoryDefaultBranchChangedJob.perform_now(repository_id: @repo.id)
        end

        assert_empty(CodeScanningAlertRevision.where(repository_id: @repo.id))
        refute_empty(CodeScanningAlertRevision.where(repository_id: other_repo.id))
        refute_empty(CodeScanningAlertRevision.where(repository_id: other_org_repo.id))

        GitHub.dogstats.count("security_overview_analytics.reset.code_scanning_alert_revisions.deleted", target_alert_count)
      end

      test "enqueues summary rollup job for the repo repo" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)

        RepositoryDefaultBranchChangedJob.perform_now(repository_id: @repo.id)

        assert_enqueued_jobs 1, only: UpdateFeatureStatusSummaryJob
      end

      test "enqueues backfill job for the repo" do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)

        Timecop.freeze do
          assert_enqueued_with(job: Initialization::Repositories::CodeScanningAlertsJob, at: 5.minutes.from_now, args: [{ repository_id: @repo.id }]) do
            RepositoryDefaultBranchChangedJob.perform_now(repository_id: @repo.id)
          end
        end
      end

      test "does not run if repo is soft-deleted" do
        CodeScanningAlertRevision.expects(:throttle_writes_with_retry).never
        Initialization::Repositories::CodeScanningAlertsJob.expects(:perform_later).never

        repo = create(:deleted_repository, owner: @org)
        RepositoryDefaultBranchChangedJob.perform_now(repository_id: repo.id)
      end

      test "does not run if repo should not handle repo lifecycle events" do
        TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).returns(false)

        CodeScanningAlertRevision.expects(:throttle_writes_with_retry).never
        Initialization::Repositories::CodeScanningAlertsJob.expects(:perform_later).never

        RepositoryDefaultBranchChangedJob.perform_now(repository_id: @repo.id)
      end
    end

    context "pubsub" do
      test "enqueues job when repo default branch is updated" do
        # Use handle creation here because the factorybot creation path doesn't invoke orchestration
        repo = ::Repository.handle_creation(
          @owner,
          @org.login,
          {
            name: "fancy-test-repo",
            public: false,
          },
        ).repository

        metadata = { message: "blah", committer: repo.owner }
        commit = repo.commits.create(metadata) {}

        # Setup second branch, on top of default one
        repo.heads.create("other", commit, repo.owner)

        clear_enqueued_jobs

        assert_enqueued_with(job: RepositoryDefaultBranchChangedJob, args: [{ repository_id: repo.id }]) do
          repo.update_default_branch("other")
        end
      end
    end

    context "resiliency" do
      test "retries on common exceptions" do
        assert_retry_conditions(job: RepositoryDefaultBranchChangedJob, args: [{ repository_id: @repo.id }])
      end
    end
  end
end
