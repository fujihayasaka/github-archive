# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class Initialization
    class UserJobTest < GitHub::TestCase
      include JobTestHelper

      fixtures do
        @user = create(:user)
        @repos = create_list(:repository, 10, owner: @user, force_user_owned: true)
      end

      setup do
        SecurityCenter::SecurityFeatures.stubs(
          code_scanning_enabled_for_instance?: true,
          secret_scanning_enabled_for_instance?: true,
          dependabot_alerts_enabled_for_instance?: true,
        )
      end

      test "it enqueues an initialization job for each EMU or Enterprise user repo" do
        if TestEnv.test_with_all_emus? || GitHub.enterprise?
          perform_enqueued_jobs(only: UserJob) do
            UserJob.perform_later(user_id: @user.id)
          end

          assert_enqueued_jobs(@user.repositories.size, only: Repositories::SecretScanningAlertsJob)
          assert_enqueued_jobs(@user.repositories.size, only: Repositories::RepoMetadataJob)
          assert_enqueued_jobs(@user.repositories.size, only: Repositories::FeatureEnablementJob)

          assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob)
          assert_no_enqueued_jobs(only: Repositories::DependabotAlertsJob)

          assert SecurityOverviewAnalytics::Initialization.for(@user).all_initialized?
        end
      end

      context "when repos are soft-deleted" do
        test "it does not enqueue repo jobs for them" do
          if TestEnv.test_with_all_emus? || GitHub.enterprise?
            ::Repository.where(id: @repos.map(&:id)).destroy_all
            create(:repository, :soft_deleted, owner: @user, force_user_owned: true)

            perform_enqueued_jobs(only: UserJob) do
              UserJob.perform_later(user_id: @user.id)
            end

            assert_no_enqueued_jobs(only: Repositories::RepoMetadataJob)
            assert_no_enqueued_jobs(only: Repositories::FeatureEnablementJob)
            assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob)
            assert_no_enqueued_jobs(only: Repositories::SecretScanningAlertsJob)
            assert_no_enqueued_jobs(only: Repositories::DependabotAlertsJob)

            assert SecurityOverviewAnalytics::Initialization.for(@user).all_initialized?
          end
        end
      end

      context "when on GHES", enterprise_only: true do
        test "it does not enqueue initialization job for feature that is not available" do
          SecurityCenter::SecurityFeatures.expects(:secret_scanning_enabled_for_instance?).at_least_once.returns(false)
          refute SecurityOverviewAnalytics::Initialization.for(@user).all_initialized?

          perform_enqueued_jobs(only: UserJob) do
            UserJob.perform_later(user_id: @user.id)
          end

          assert_enqueued_jobs(@user.repositories.size, only: Repositories::RepoMetadataJob)
          assert_enqueued_jobs(@user.repositories.size, only: Repositories::FeatureEnablementJob)

          assert_no_enqueued_jobs(only: Repositories::CodeScanningAlertsJob)
          assert_no_enqueued_jobs(only: Repositories::SecretScanningAlertsJob)
          assert_no_enqueued_jobs(only: Repositories::DependabotAlertsJob)

          assert SecurityOverviewAnalytics::Initialization.for(@user).all_initialized?
        end
      end
    end
  end
end
