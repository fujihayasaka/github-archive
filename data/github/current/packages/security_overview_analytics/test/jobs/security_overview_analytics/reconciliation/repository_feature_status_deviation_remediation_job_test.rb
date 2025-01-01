# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryFeatureStatusDeviationRemediationJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        # Business & user
        if GitHub.enterprise?
          @biz = T.let(create(:global_business), T.nilable(::Business))
          @user = T.let(create(:user), T.nilable(::User))
        else
          @biz = T.let(create(:business, :enterprise_managed), T.nilable(::Business))
          @user = T.let(create(:emu, business: @biz), T.nilable(::User))
        end
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(true)

        ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
          .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_eligible", 0))
      end

      context "#perform for organization" do
        context "when repository feature status record doesn't exist" do
          test "does nothing if repository doesn't exist neither" do
            org = create(:organization)
            repo = create(:repository, owner: org)
            repository_id = repo.id
            repo.destroy!
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repository_id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is deleted" do
            user = create(:user)
            org = create(:organization)
            repo = create(:repository, owner: org)
            repo.remove(user)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            org = create(:organization)
            repo = create(:repository, owner: org)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)
            org = create(:organization)
            repo = create(:repository, owner: org)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "creates missing metadata record for legit repository" do
            org = create(:organization)
            repo = create(:repository, owner: org)
            now = Time.current
            Timecop.freeze(now) do
              date_id = Date.id_from_time(now)
              refute FeatureStatusRevision.find_by(repository_id: repo.id, date_id:)
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
                end
              end
              assert FeatureStatusRevision.find_by(repository_id: repo.id, date_id:)
              assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
                "remediation:feature_status_upserted"
              ]
            end
          end
        end

        context "when repository feature status record exists" do
          test "does nothing if repository doesn't exist neither" do
            feature_status = create(:security_overview_analytics_feature_status_revision)
            feature_status.repository.destroy!
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is deleted" do
            user = create(:user)
            feature_status = create(:security_overview_analytics_feature_status_revision)
            feature_status.repository.remove(user)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            feature_status = create(:security_overview_analytics_feature_status_revision)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)
            feature_status = create(:security_overview_analytics_feature_status_revision)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "updates feature status for legit repository" do
            now = Time.current
            ::SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
            ::SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
            feature_status = create(
              :security_overview_analytics_feature_status_revision,
              dependabot_alerts_enabled: false,
              advanced_security_enabled: false
            )
            Timecop.freeze(now) do
              date_id = Date.id_from_time(now)
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
                end
              end
              assert feature_status.reload.dependabot_alerts_enabled
              assert feature_status.advanced_security_enabled
              assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
                "remediation:feature_status_upserted"
              ]
            end
          end

          test "updates updated_at when updates the record" do
            ::SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
            feature_status = create(
              :security_overview_analytics_feature_status_revision,
              advanced_security_enabled: false
            )
            assert_changes(
              -> { feature_status.reload.updated_at }
            ) do
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
                end
              end
              assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
                "remediation:feature_status_upserted"
              ]
            end
          end
        end
      end

      context "#perform for user" do
        context "when repository feature status record doesn't exist" do
          test "does nothing if repository doesn't exist neither" do
            repo = create(:repository, owner: @user)
            repository_id = repo.id
            repo.destroy!
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repository_id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is deleted" do
            repo = create(:repository, owner: @user)
            repo.remove(@user)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            repo = create(:repository, owner: @user)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)
            repo = create(:repository, owner: @user)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
              end
            end
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "creates missing metadata record for legit repository" do
            repo = create(:repository, owner: @user)
            now = Time.current
            Timecop.freeze(now) do
              date_id = Date.id_from_time(now)
              refute FeatureStatusRevision.find_by(repository_id: repo.id, date_id:)
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
                end
              end
              assert FeatureStatusRevision.find_by(repository_id: repo.id, date_id:)
              assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
                "remediation:feature_status_upserted"
              ]
            end
          end
        end

        context "when repository feature status record exists" do
          test "does nothing if repository doesn't exist neither" do
            user_repo = create(:repository, owner: @user)
            user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)
            feature_status = create(:security_overview_analytics_feature_status_revision, repository_metadata: user_repo_metadata)
            user_repo.destroy!
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository is deleted" do
            user_repo = create(:repository, owner: @user)
            user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)
            feature_status = create(:security_overview_analytics_feature_status_revision, repository_metadata: user_repo_metadata)
            user_repo.remove(@user)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is out of scope" do
            TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
            user_repo = create(:repository, owner: @user)
            user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)
            feature_status = create(:security_overview_analytics_feature_status_revision, repository_metadata: user_repo_metadata)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "does nothing if repository owner is not initialized" do
            Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)
            feature_status = create(:security_overview_analytics_feature_status_revision)
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
              assert_nothing_raised do
                RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
              end
            end
            assert FeatureStatusRevision.find_by(repository_id: feature_status.repository_id, date_id: feature_status.date_id)
            assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
              "remediation:no_op"
            ]
          end

          test "updates feature status for legit repository" do
            now = Time.current
            ::SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
            ::SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)

            user_repo = create(:repository, owner: @user)
            user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)

            feature_status = create(
              :security_overview_analytics_feature_status_revision,
              dependabot_alerts_enabled: false,
              advanced_security_enabled: false,
              repository_metadata: user_repo_metadata
            )
            Timecop.freeze(now) do
              date_id = Date.id_from_time(now)
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
                end
              end
              assert feature_status.reload.dependabot_alerts_enabled
              assert feature_status.advanced_security_enabled
              assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
                "remediation:feature_status_upserted"
              ]
            end
          end

          test "updates updated_at when updates the record" do
            ::SecurityProduct::AdvancedSecurity.any_instance.stubs(:enabled?).returns(true)
            user_repo = create(:repository, owner: @user)
            user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)
            feature_status = create(
              :security_overview_analytics_feature_status_revision,
              advanced_security_enabled: false,
              repository_metadata: user_repo_metadata
            )
            assert_changes(
              -> { feature_status.reload.updated_at }
            ) do
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationRemediationJob do
                assert_nothing_raised do
                  RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: feature_status.repository_id)
                end
              end
              assert_dogstats_increment 1, "security_overview_analytics.repository_feature_status_deviation_remediation.completed", tags: [
                "remediation:feature_status_upserted"
              ]
            end
          end
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same input" do
          org = create(:organization)
          repo = create(:repository, owner: org)
          assert_enqueued_jobs 2, only: RepositoryFeatureStatusDeviationRemediationJob do
            RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
            RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hohoho", repository_id: repo.id)
            RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id: "hahaha", repository_id: repo.id)
          end
        end
      end

      context "resiliency" do
        test "retries on standard conditions" do
          org = create(:organization)
          repo = create(:repository, owner: org)

          assert_retry_conditions(job: RepositoryFeatureStatusDeviationRemediationJob, args: [{ repository_id: repo.id, session_id: "foobar" }])
        end

        test "retries on transient errors" do
          org = create(:organization)
          repo = create(:repository, owner: org)

          RepositoryFeatureStatusDeviationRemediationJob::RETRYABLE_EXCEPTIONS.each do |error|
            assert_retry_on_error(
              error,
              RepositoryFeatureStatusDeviationRemediationJob,
              [{ repository_id: repo.id, session_id: "foobar" }],
              true,
            )
          end
        end
      end
    end
  end
end
