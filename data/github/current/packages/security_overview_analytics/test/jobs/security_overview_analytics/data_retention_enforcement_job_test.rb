# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class DataRetentionEnforcementJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    context "#perform" do
      test "deletes revision data if more than one revision is older than retention limit" do
        now = Time.now
        date_now = create(:soa_date, date_value: now)

        three_years_ago = 3.years.ago
        date_three_years_ago = create(:security_overview_analytics_date, date_value: three_years_ago)
        date_older_than_date_three_years_ago = create(:security_overview_analytics_date, date_value: three_years_ago - 1.day)

        org = create(:business_plus_organization)
        repo = create(:repository, owner: org)
        metadata = create(:soa_repository, repository: repo)

        # Table with only one revision that is older than 2 years retention limit
        # No revision will be deleted.
        create(:soa_feature_status_revision, repository_metadata: metadata, date: date_three_years_ago)

        # Table with only one revision that is within 2 years retention limit
        # No revision will be deleted.
        create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date_now)

        # Table with revisions within 2 years retention limit and one revision older than 2 years
        # No revision will be deleted.
        create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date_now)
        create(
          :soa_code_scanning_alert_revision,
          repository_metadata: metadata,
          date: date_three_years_ago,
          next_revision_date_id: Date.id_from_time(now)
        )

        # Table with revisions within 2 years retention limit and MORE THAN ONE revisions older than 2 years
        # Only one revision older than 2 years will be kept
        create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date_now)
        create(
          :soa_secret_scanning_alert_revision,
          repository_metadata: metadata,
          date: date_three_years_ago,
          next_revision_date_id: Date.id_from_time(now)
        )
        revision_to_be_deleted = create(
          :soa_secret_scanning_alert_revision,
          repository_metadata: metadata,
          date: date_older_than_date_three_years_ago,
          next_revision_date_id: Date.id_from_time(three_years_ago)
        )

        create(:soa_code_scanning_pr_alert, repository_metadata: metadata, alert_number: 1, date_id: date_now.id)
        pr_alert_to_be_deleted = create(:soa_code_scanning_pr_alert, repository_metadata: metadata, alert_number: 2, date_id: Date.id_from_time(three_years_ago))

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 2, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 3, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 2, CodeScanningPullRequestAlert.where(repository_id: repo.id).count
        refute_nil SecretScanningAlertRevision.find_by(id: revision_to_be_deleted.id)
        refute_nil CodeScanningPullRequestAlert.find_by(id: pr_alert_to_be_deleted.id)

        assert_performed_jobs 1, only: DataRetentionEnforcementJob do
          DataRetentionEnforcementJob.perform_later
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 2, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 2, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count
        assert_nil SecretScanningAlertRevision.find_by(id: revision_to_be_deleted.id)
        assert_nil CodeScanningPullRequestAlert.find_by(id: pr_alert_to_be_deleted.id)

        assert_dogstats_distribution 5, "security_overview_analytics.data_retention_enforcement.dist"
        assert_dogstats_count 1, "security_overview_analytics.data_retention_enforcement.revisions_to_remove", tags: ["table:#{SecretScanningAlertRevision.table_name}"]
        assert_dogstats_count 1, "security_overview_analytics.data_retention_enforcement.revisions_to_remove", tags: ["table:#{CodeScanningPullRequestAlert.table_name}"]
      end
    end

    context "batched job" do
      test "queues subsequent jobs for batching" do
        org = create(:organization).tap do |o|
          9.times do
            create(:repository, owner: o).tap do |r|
              create(:soa_repository, repository: r)
            end
          end
        end

        DataRetentionEnforcementJob.stub_const(:BATCH_SIZE, 5) do
          assert_performed_jobs 2, only: DataRetentionEnforcementJob do
            perform_enqueued_jobs only: DataRetentionEnforcementJob do
              DataRetentionEnforcementJob.perform_later
            end
          end
        end

        assert_dogstats_distribution 1, "batched_job.total_time.dist"
      end
    end

    context "hash lock" do
      test "allows one job to be enqueued at a time no matter the input" do
        assert_enqueued_jobs 1, only: DataRetentionEnforcementJob do
          DataRetentionEnforcementJob.perform_later
          DataRetentionEnforcementJob.perform_later
          DataRetentionEnforcementJob.perform_later(min_next_date_id: 12345678)
        end
      end
    end
  end
end
