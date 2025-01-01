# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class RepositoryDataCleanupJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    fixtures do
      if GitHub.enterprise?
        @biz = create(:global_business)
        @user = create(:user)
      else
        @biz = create(:business, :enterprise_managed)
        @user = create(:emu, business: @biz)
      end

      @org = create(:enterprise_linked_organization)

      # As long as one feature is marked as initialized, job should not delete any data for the tenant.
      Initialization.for(@org).set_type_to_initialized(type: Initialization::Type::RepositoryMetadata)
      Initialization.for(@user).set_type_to_initialized(type: Initialization::Type::RepositoryMetadata)
    end

    setup do
      AdvancedSecurity::Features::User::AdvancedSecurity.any_instance.stubs(:feature_available?).returns(true)
    end

    context "#perform" do
      test "does not delete org repository data if it exists and tenant is validated and initialized" do
        now = Time.now
        repo = create(:repository, owner: @org).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        assert_performed_jobs 1, only: RepositoryDataCleanupJob do
          RepositoryDataCleanupJob.perform_later
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        refute_dogstats_increment "security_overview_analytics.repository_data_cleanup.repository_to_remove"
        refute_dogstats_distribution "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
      end

      test "does not delete user repository data if it exists and tenant is validated and initialized" do
        now = Time.now
        repo = create(:repository, owner: @user).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        assert_performed_jobs 1, only: RepositoryDataCleanupJob do
          RepositoryDataCleanupJob.perform_later
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        refute_dogstats_increment "security_overview_analytics.repository_data_cleanup.repository_to_remove"
        refute_dogstats_distribution "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
      end

      test "deletes repository data for repositories that have been deleted" do
        now = Time.now
        repo = create(:deleted_repository, owner: @org).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        assert_performed_jobs 1, only: RepositoryDataCleanupJob do
          RepositoryDataCleanupJob.perform_later
        end

        assert_equal 0, Repository.where(repository_id: repo.id).count
        assert_equal 0, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 0, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 0, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 0, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 0, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 0, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:repo_not_found"]
        assert_dogstats_distribution 7, "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
      end

      test "deletes repository data if owned by regular dotcom user", skip_enterprise: true do
        now = Time.now
        user = create(:user)
        repo = create(:repository, owner: user).tap do |r|
          metadata = create(:soa_repository, repository_id: r.id, organization_id: @org.id, name: r.name, archived: r.archived?, visibility: r.visibility, event_time: now)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        assert_equal 1, Repository.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        assert_performed_jobs 1, only: RepositoryDataCleanupJob do
          RepositoryDataCleanupJob.perform_later
        end

        assert_equal 0, Repository.where(repository_id: repo.id).count
        assert_equal 0, FeatureStatus.where(repository_id: repo.id).count
        assert_equal 0, FeatureStatusRevision.where(repository_id: repo.id).count
        assert_equal 0, DependabotAlertRevision.where(repository_id: repo.id).count
        assert_equal 0, CodeScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 0, SecretScanningAlertRevision.where(repository_id: repo.id).count
        assert_equal 0, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

        assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:not_org_or_emu_owned_repo"]
        assert_dogstats_distribution 7, "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
      end

      test "re-initialize organization if it is in-scope but not initialized" do
        now = Time.now
        org = create(:business_plus_organization)
        create(:repository, owner: org).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        FanoutScheduler.expects(:initialize_for).once
        assert_enqueued_jobs 1, only: Initialization::OrganizationJob do
          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end
        end

        refute_dogstats_increment "security_overview_analytics.repository_data_cleanup.repository_to_remove"
        refute_dogstats_distribution "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
        assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_initialize", tags: ["reason:tenant_not_initialized"]
      end

      test "re-initialize user if it is in-scope but not initialized" do
        user = if GitHub.enterprise?
          create(:user, business: @biz)
        else
          create(:emu, business: @biz)
        end

        now = Time.now
        create(:repository, owner: user).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        FanoutScheduler.expects(:initialize_for).once
        assert_enqueued_jobs 1, only: Initialization::UserJob do
          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end
        end

        refute_dogstats_increment "security_overview_analytics.repository_data_cleanup.repository_to_remove"
        refute_dogstats_distribution "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
        assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_initialize", tags: ["reason:tenant_not_initialized"]
      end

      test "deletes repository data if repository tenant is not in scope" do
        now = Time.now
        org = create(:organization)
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
        create(:repository, owner: org).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        # TODO: https://github.com/github/security-center/issues/4161
        # Org should be scheduled for offboarding

        assert_performed_jobs 1, only: RepositoryDataCleanupJob do
          RepositoryDataCleanupJob.perform_later
        end

        assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:tenant_not_in_scope"]
      end

      test "deletes repository data if tenant initialized but not in scope" do
        now = Time.now
        org = create(:organization)
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
        Initialization.for(org).set_type_to_initialized(type: Initialization::Type::RepositoryMetadata)
        create(:repository, owner: org).tap do |r|
          metadata = create(:soa_repository, repository: r)
          date = create(:soa_date, date_value: now)
          create(:soa_feature_status, repository_metadata: metadata)
          create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
          create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
          create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
        end

        # TODO: https://github.com/github/security-center/issues/4161
        # Org should be scheduled for offboarding

        assert_performed_jobs 1, only: RepositoryDataCleanupJob do
          RepositoryDataCleanupJob.perform_later
        end
      end

      context "when orphaned revisions data exists" do
        test "does not delete if repository tenant is validated and initialized" do
          now = Time.now
          repo = create(:repository, owner: @org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            date = create(:soa_date, date_value: now)
            create(:soa_feature_status, repository_metadata: metadata)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
            create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
            metadata.destroy
          end

          assert_equal 0, Repository.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
          assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end

          assert_equal 0, Repository.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
          assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

          refute_dogstats_increment "security_overview_analytics.repository_data_cleanup.repository_to_remove"
          refute_dogstats_distribution "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
        end

        test "reinitialize the tenant if it is in-scope but not initialized" do
          now = Time.now
          org = create(:business_plus_organization)
          create(:repository, owner: org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            date = create(:soa_date, date_value: now)
            create(:soa_feature_status, repository_metadata: metadata)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
            create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
            metadata.destroy
          end

          FanoutScheduler.expects(:initialize_for).once
          assert_enqueued_jobs 1, only: Initialization::OrganizationJob do
            assert_performed_jobs 1, only: RepositoryDataCleanupJob do
              RepositoryDataCleanupJob.perform_later
            end
          end

          refute_dogstats_increment "security_overview_analytics.repository_data_cleanup.repository_to_remove"
          refute_dogstats_distribution "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
          assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_initialize", tags: ["reason:tenant_not_initialized"]
        end

        test "deletes orphaned records if tenant is not in scope" do
          now = Time.now
          org = create(:organization)
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          create(:repository, owner: org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            date = create(:soa_date, date_value: now)
            create(:soa_feature_status, repository_metadata: metadata)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
            create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
            metadata.destroy
          end

          # TODO: https://github.com/github/security-center/issues/4161
          # Org should be scheduled for offboarding

          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end

          assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:tenant_not_in_scope"]
        end

        test "deletes orphaned records if tenant initialized but not in scope" do
          now = Time.now
          org = create(:organization)
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          Initialization.for(org).set_type_to_initialized(type: Initialization::Type::RepositoryMetadata)
          create(:repository, owner: org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            date = create(:soa_date, date_value: now)
            create(:soa_feature_status, repository_metadata: metadata)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
            create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
            metadata.destroy
          end

          # TODO: https://github.com/github/security-center/issues/4161
          # Org should be scheduled for offboarding

          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end

          assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:tenant_not_in_scope"]
        end

        test "deletes orphaned records if repo owned by user", skip_enterprise: true do
          now = Time.now
          user = create(:user)
          repo = create(:repository, owner: user).tap do |r|
            metadata = create(:soa_repository, repository_id: r.id, organization_id: @org.id, name: r.name, archived: r.archived?, visibility: r.visibility, event_time: now)
            date = create(:soa_date, date_value: now)
            create(:soa_feature_status, repository_metadata: metadata)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
            create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
            metadata.destroy
          end

          assert_equal 0, Repository.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
          assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end

          assert_equal 0, Repository.where(repository_id: repo.id).count
          assert_equal 0, FeatureStatus.where(repository_id: repo.id).count
          assert_equal 0, FeatureStatusRevision.where(repository_id: repo.id).count
          assert_equal 0, DependabotAlertRevision.where(repository_id: repo.id).count
          assert_equal 0, CodeScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 0, SecretScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 0, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

          assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:not_org_or_emu_owned_repo"]
          assert_dogstats_distribution 7, "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
        end

        test "deletes orphaned records if repo deleted" do
          now = Time.now
          repo = create(:deleted_repository, owner: @org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            date = create(:soa_date, date_value: now)
            create(:soa_feature_status, repository_metadata: metadata)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date)
            create(:soa_dependabot_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_secret_scanning_alert_revision, repository_metadata: metadata, date: date)
            create(:soa_code_scanning_pr_alert, repository_metadata: metadata)
            metadata.destroy
          end

          assert_equal 0, Repository.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatus.where(repository_id: repo.id).count
          assert_equal 1, FeatureStatusRevision.where(repository_id: repo.id).count
          assert_equal 1, DependabotAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, SecretScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 1, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

          assert_performed_jobs 1, only: RepositoryDataCleanupJob do
            RepositoryDataCleanupJob.perform_later
          end

          assert_equal 0, Repository.where(repository_id: repo.id).count
          assert_equal 0, FeatureStatus.where(repository_id: repo.id).count
          assert_equal 0, FeatureStatusRevision.where(repository_id: repo.id).count
          assert_equal 0, DependabotAlertRevision.where(repository_id: repo.id).count
          assert_equal 0, CodeScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 0, SecretScanningAlertRevision.where(repository_id: repo.id).count
          assert_equal 0, CodeScanningPullRequestAlert.where(repository_id: repo.id).count

          assert_dogstats_increment 1, "security_overview_analytics.repository_data_cleanup.repository_to_remove", tags: ["reason:repo_not_found"]
          assert_dogstats_distribution 7, "security_overview_analytics.repository_data_cleanup.remove_repositories.dist"
        end
      end
    end

    context "batched job" do
      test "queues subsequent jobs for batching" do
        create(:organization).tap do |o|
          9.times do
            create(:repository, owner: o).tap do |r|
              create(:soa_repository, repository: r)
            end
          end
        end

        RepositoryDataCleanupJob.stub_const(:BATCH_SIZE, 5) do
          assert_performed_jobs 2, only: RepositoryDataCleanupJob do
            perform_enqueued_jobs only: RepositoryDataCleanupJob do
              RepositoryDataCleanupJob.perform_later
            end
          end
        end

        assert_dogstats_distribution 1, "batched_job.total_time.dist"
      end
    end
  end
end
