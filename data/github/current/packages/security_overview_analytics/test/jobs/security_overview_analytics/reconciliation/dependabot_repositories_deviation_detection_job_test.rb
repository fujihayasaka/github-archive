# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  module Reconciliation
    class DependabotRepositoriesDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        @biz = create(:business)
        @org = create(:organization, business: @biz)
        @repo = create(:repository, owner: @org, name: "foo")
        @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
        create(:soa_dependabot_alert_revision, repository_metadata: @soa_repo)
      end

      setup do
        @stats_tags = ["metric_type:dependabot_alerts"].compact
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(true)
        # Stub info logging, otherwise we'll have to separately assert "Session locked" in every test.
        GitHub.logger.stubs(:info).returns(true)

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        end
      end

      context "#perform" do
        context "when analytics has no alerts for repository" do
          test "it enqueues alert deviation job" do
            DependabotAlertRevision.delete_all

            GitHub.logger.expects(:info).with(
              "Deviation found.",
              anything
              ).never

            assert_enqueued_with(job: DependabotAlertsDeviationDetectionJob, args: [repository_id: @repo.id, last_session_started_at: nil]) do
              assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
                DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: @org.id)
              end
            end

            refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          end
        end

        test "queues alerts deviation detection job when analytics has alerts for repository" do
          assert_enqueued_with(
              job: DependabotAlertsDeviationDetectionJob,
              args: -> (job_args) do
                assert_equal @repo.id, job_args.dig(0, :repository_id)
                assert_nil job_args.dig(0, :last_session_started_at)
              end) do
            assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
              DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: @org.id)
            end
          end
        end
      end

      context "#around_enqueue" do
        test "raises ArgumentError if missing organization_id" do
          assert_enqueued_jobs 0, only: DependabotRepositoriesDeviationDetectionJob do
            assert_raises ArgumentError do
              DependabotRepositoriesDeviationDetectionJob.perform_later
            end
          end
        end
      end

      context "#around_perform" do
        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          DependabotRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          DependabotRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
            DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(false)

          DependabotRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          DependabotRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
            DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
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

            assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
              DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id, session_started_at: Time.now.utc)
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

          DependabotRepositoriesDeviationDetectionJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: DependabotRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: DependabotRepositoriesDeviationDetectionJob do
                DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end
          end

          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same organization" do
          org = create(:organization)
          assert_enqueued_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
            DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
          end
        end
      end

      context "resiliency" do
        test "retries on standard conditions" do
          org = create(:organization)
          Session.any_instance.stubs(:locked?).returns(true)

          assert_retry_conditions(job: DependabotRepositoriesDeviationDetectionJob, args: [{ organization_id: org.id, session_started_at: Time.now.utc }])
        end
      end

      context "session lock" do
        test "does not allow consecutive jobs if session is still locked" do
          org = create(:organization)
          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once
          Session.any_instance.expects(:reset!).never

          Timecop.freeze do
            assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: DependabotRepositoriesDeviationDetectionJob do
                DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            assert Session.new(owner_id: org.id, type: "dependabot_alerts").locked?
          end

          Timecop.travel(1.hour.from_now) do
            assert_enqueued_jobs 0, only: DependabotRepositoriesDeviationDetectionJob do
              DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end

            assert Session.new(owner_id: org.id, type: "dependabot_alerts").locked?
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
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          Timecop.freeze do
            assert_performed_jobs 1, only: DependabotRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: DependabotRepositoriesDeviationDetectionJob do
                DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            refute Session.new(owner_id: org.id, type: "dependabot_alerts").locked?
          end
        end

        test "reset session lock when retry attempts are exhausted" do
          org = create(:organization)
          DependabotRepositoriesDeviationDetectionJob.any_instance.stubs(:perform).raises(ActiveRecord::ConnectionFailed)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          assert_performed_jobs(5, only: [DependabotRepositoriesDeviationDetectionJob]) do
            perform_enqueued_jobs only: DependabotRepositoriesDeviationDetectionJob do
              DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "dependabot_alerts").locked?
        end

        test "reset session lock on non-retryable exceptions" do
          org = create(:organization)
          DependabotRepositoriesDeviationDetectionJob.any_instance.stubs(:perform).raises(ArgumentError.new("some error"))

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          perform_enqueued_jobs only: DependabotRepositoriesDeviationDetectionJob do
            assert_raises ArgumentError do
              DependabotRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "dependabot_alerts").locked?
        end
      end
    end
  end
end
