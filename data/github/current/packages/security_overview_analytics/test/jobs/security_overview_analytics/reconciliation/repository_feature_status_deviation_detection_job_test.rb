# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryFeatureStatusDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        # Business
        @biz = if GitHub.enterprise?
          create(:global_business)
        else
          create(:business, :enterprise_managed)
        end

        @user = if GitHub.enterprise?
          create(:user, business: @biz)
        else
          create(:emu, business: @biz)
        end
      end

      setup do
        @stats_tags = ["metric_type:feature_enablement"]
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(true)

        ::Repository.any_instance.stubs(:code_scanning_auto_codeql_security_center_status)
          .returns(::Repository::SecurityCenterDependency::SecurityCenterUpdateStatus.new("not_eligible", 0))

        # Stub info logging, otherwise we'll have to separately assert "Session locked" in every test.
        GitHub.logger.stubs(:info).returns(true)
      end

      context "#perform with organization_id" do
        test "reports and queues remediation if deviation found" do
          ::SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
          feature_status = create(:security_overview_analytics_feature_status_revision, dependabot_alerts_enabled: false)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:dependabot_alerts_enabled]
            })
          ).once
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: feature_status.repository_id)).once

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: feature_status.repository_metadata.organization_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record is missing" do
          org = create(:business_plus_organization)
          repo = create(:repository, owner: org)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_data]
            })
          ).once
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: repo.id)).once

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "does not report deviation if metadata record up to date" do
          feature_status = create(:security_overview_analytics_feature_status_revision)

          GitHub.logger.expects(:info).with("Deviation found.", anything).never
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: feature_status.repository_id)).never

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: feature_status.repository_metadata.organization_id, session_id: "hohoho")
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "#perform with org owner_id" do
        test "reports and queues remediation if deviation found" do
          ::SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
          feature_status = create(:security_overview_analytics_feature_status_revision, dependabot_alerts_enabled: false)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:dependabot_alerts_enabled]
            })
          ).once
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: feature_status.repository_id)).once

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: feature_status.repository_metadata.organization_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record is missing" do
          org = create(:business_plus_organization)
          repo = create(:repository, owner: org)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_data]
            })
          ).once
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: repo.id)).once

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "does not report deviation if metadata record up to date" do
          feature_status = create(:security_overview_analytics_feature_status_revision)

          GitHub.logger.expects(:info).with("Deviation found.", anything).never
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: feature_status.repository_id)).never

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: feature_status.repository_metadata.organization_id, session_id: "hohoho")
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "#perform with user owner_id" do
        test "reports and queues remediation if deviation found" do
          user_repo = create(:repository, owner: @user)
          user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)

          ::SecurityProduct::VulnerabilityAlerts.any_instance.stubs(:enabled?).returns(true)
          feature_status = create(:security_overview_analytics_feature_status_revision, repository_metadata: user_repo_metadata, dependabot_alerts_enabled: false)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:dependabot_alerts_enabled]
            })
          ).once
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: feature_status.repository_id)).once

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: feature_status.repository_metadata.owner_id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "reports and queues remediation if metadata record is missing" do
          repo = create(:repository, owner: @user)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.deviations": [:missing_owner_repo_data]
            })
          ).once
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: repo.id)).once

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: @user.id, session_id: "hohoho")
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: @stats_tags
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end

        test "does not report deviation if metadata record up to date" do
          user_repo = create(:repository, owner: @user)
          user_repo_metadata = create(:security_overview_analytics_repository, repository: user_repo)

          feature_status = create(:security_overview_analytics_feature_status_revision, repository_metadata: user_repo_metadata)

          GitHub.logger.expects(:info).with("Deviation found.", anything).never
          RepositoryFeatureStatusDeviationRemediationJob.expects(:perform_later).with(has_entries(repository_id: feature_status.repository_id)).never

          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: feature_status.repository_metadata.owner_id, session_id: "hohoho")
          end

          refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "#around_enqueue" do
        test "raises ArgumentError if missing organization_id and owner_id" do
          assert_enqueued_jobs 0, only: RepositoryFeatureStatusDeviationDetectionJob do
            assert_raises ArgumentError do
              RepositoryFeatureStatusDeviationDetectionJob.perform_later(session_id: "woof")
            end
          end
        end
      end

      context "#around_perform with organization_id" do
        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)

          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "dependabot_alerts")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
              RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id, session_started_at: Time.now.utc)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "#around_perform with owner_id" do
        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::FeatureEnablement).returns(false)

          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:next_batch).never
          RepositoryFeatureStatusDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
            RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_id: "hohoho")
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "dependabot_alerts")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
              RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_started_at: Time.now.utc)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "batched job" do
        test "queues subsequent jobs for batching" do
          org = create(:organization).tap do |o|
            9.times do
              create(:repository, owner: o)
            end
          end

          RepositoryFeatureStatusDeviationDetectionJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: RepositoryFeatureStatusDeviationDetectionJob do
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationDetectionJob do
                RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id, session_id: "hohoho")
              end
            end
          end

          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "resiliency" do
        test "retries on standard conditions" do
          org = create(:organization)
          Session.any_instance.stubs(:locked?).returns(true)
          assert_retry_conditions(job: RepositoryFeatureStatusDeviationDetectionJob, args: [{ organization_id: org.id, session_started_at: Time.now.utc }])
        end

        test "retries on transient errors" do
          org = create(:organization)
          Session.any_instance.stubs(:locked?).returns(true)
          RepositoryFeatureStatusDeviationDetectionJob::RETRYABLE_EXCEPTIONS.each do |error|
            assert_retry_on_error(
              error,
              RepositoryFeatureStatusDeviationDetectionJob,
              [{ organization_id: org.id, session_started_at: Time.now.utc }],
              true,
            )
          end
        end
      end

      context "session lock" do
        test "does not allow consecutive jobs if session is still locked" do
          org = create(:organization)
          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once
          Session.any_instance.expects(:reset!).never

          Timecop.freeze do
            assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationDetectionJob do
                RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            assert Session.new(owner_id: org.id, type: "feature_enablement").locked?
          end

          Timecop.travel(1.hour.from_now) do
            assert_enqueued_jobs 0, only: RepositoryFeatureStatusDeviationDetectionJob do
              RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id)
            end

            assert Session.new(owner_id: org.id, type: "feature_enablement").locked?
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_locked"]
        end

        test "reset session lock if job fails tenant validation" do
          org = create(:organization)
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once

          Timecop.freeze do
            assert_performed_jobs 1, only: RepositoryFeatureStatusDeviationDetectionJob do
              perform_enqueued_jobs only: RepositoryFeatureStatusDeviationDetectionJob do
                RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            refute Session.new(owner_id: org.id, type: "feature_enablement").locked?
          end
        end

        test "reset session lock when retry attempts are exhausted" do
          org = create(:organization)
          RepositoryFeatureStatusDeviationDetectionJob.any_instance.stubs(:perform).raises(ActiveRecord::ConnectionFailed)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once

          assert_performed_jobs(5, only: [RepositoryFeatureStatusDeviationDetectionJob]) do
            perform_enqueued_jobs only: RepositoryFeatureStatusDeviationDetectionJob do
              RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "feature_enablement").locked?
        end

        test "reset session lock on non-retryable exceptions" do
          org = create(:organization)
          RepositoryFeatureStatusDeviationDetectionJob.any_instance.stubs(:perform).raises(ArgumentError.new("some error"))

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "feature_enablement"
            })
          ).once

          perform_enqueued_jobs only: RepositoryFeatureStatusDeviationDetectionJob do
            assert_raises ArgumentError do
              RepositoryFeatureStatusDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "feature_enablement").locked?
        end
      end
    end
  end
end
