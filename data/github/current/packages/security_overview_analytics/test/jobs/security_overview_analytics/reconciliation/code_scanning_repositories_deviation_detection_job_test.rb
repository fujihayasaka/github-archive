# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  module Reconciliation
    class CodeScanningRepositoriesDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      fixtures do
        @biz = create(:business)
        @org = create(:organization, business: @biz)
        @repo = create(:repository, owner: @org, name: "foo")
        @soa_repo = create(:security_overview_analytics_repository, repository: @repo)

        @open_alerts_count = 3.times do |i|
          date_id = 20231001 + i
          alert_number = i
          create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date_id:, alert_number:)
        end

        @closed_alerts_count = 1.times do |i|
          date_id = 20231001 + i
          alert_number = 100 + i
          create(:soa_code_scanning_alert_revision, repository_metadata: @soa_repo, date_id:, alert_number:, alert_resolved: true)
        end
      end

      setup do
        @stats_tags = ["metric_type:code_scanning_alerts"].compact

        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).returns(true)
        # Stub info logging, otherwise we'll have to separately assert "Session locked" in every test.
        GitHub.logger.stubs(:info).returns(true)

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(true)
        end
      end

      context "#perform" do
        context "when analytics has no alerts for repository" do
          test "it enqueues initialization job" do
            CodeScanningAlertRevision.delete_all
            Session.any_instance.stubs(:locked?).returns(true)

            assert_enqueued_with(job: Initialization::Repositories::CodeScanningAlertsJob, args: [repository_id: @repo.id]) do
              CodeScanningRepositoriesDeviationDetectionJob.perform_now(organization_id: @org.id, last_session_started_at: Time.now.utc)
            end

            assert_dogstats_increment(1, "security_overview_analytics.reconciliation.deviation", tags: ["deviation:missing_repository"])
          end
        end

        context "when analytics has alerts for repository" do
          test "it enqueues alert deviation detection job" do
            Session.any_instance.stubs(:locked?).returns(true)
            last_session_started_at = 1.week.ago

            assert_enqueued_with(
                job: CodeScanningAlertsDeviationDetectionJob,
                args: -> (job_args) do
                  assert_equal @repo.id, job_args.dig(0, :repository_id)
                  assert_equal last_session_started_at, job_args.dig(0, :last_session_started_at)
                end) do
              CodeScanningRepositoriesDeviationDetectionJob.perform_now(
                organization_id: @org.id,
                last_session_started_at:
              )
            end
          end
        end
      end

      context "when the organization_id is not provided" do
        test "it raises ArgumentError" do
          assert_no_enqueued_jobs(only: CodeScanningRepositoriesDeviationDetectionJob) do
            assert_raises_with_message(ArgumentError, "Missing organization_id.") do
              CodeScanningRepositoriesDeviationDetectionJob.perform_later
            end

            refute CodeScanningRepositoriesDeviationDetectionJob.new.locked?
          end
        end
      end

      context "when on GHES", enterprise_only: true do
        test "it doesn't perform the job if feature not configured" do
          SecurityCenter::SecurityFeatures.stubs(:code_scanning_enabled_for_instance?).returns(false)

          ::Turboscan::ResultsClient.any_instance.expects(:alerts).never
          Session.any_instance.expects(:reset!).once

          perform_enqueued_jobs(only: CodeScanningRepositoriesDeviationDetectionJob) do
            CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: @org.id)
          end

          assert_dogstats_increment(1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:feature_unavailable"])
        end
      end

      context "when the organization is not in scope" do
        test "it doesn't perform the job" do
          TenantValidationHelper.expects(:is_owner_in_scope?).returns(false)

          ::Turboscan::ResultsClient.any_instance.expects(:alerts).never
          Session.any_instance.expects(:reset!).once

          perform_enqueued_jobs(only: CodeScanningRepositoriesDeviationDetectionJob) do
            CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: @org.id)
          end

          assert_dogstats_increment(1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"])
        end
      end

      context "when the organization has not been initialized" do
        test "it doesn't perform the job" do
          Initialization.any_instance.stubs(:initialized?).returns(false)

          ::Turboscan::ResultsClient.any_instance.expects(:alerts).never
          Session.any_instance.expects(:reset!).once

          perform_enqueued_jobs(only: CodeScanningRepositoriesDeviationDetectionJob) do
            CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: @org.id)
          end

          assert_dogstats_increment(1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"])
        end
      end

      context "when session has been reset" do
        test "stops the perform" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "code_scanning_alert")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: CodeScanningRepositoriesDeviationDetectionJob do
              CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id, session_started_at: Time.now.utc)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "resiliency" do
        test "it retries on standard conditions" do
          Session.any_instance.stubs(:locked?).returns(true)
          assert_retry_conditions(
            job: CodeScanningRepositoriesDeviationDetectionJob,
            args: [organization_id: @org.id, session_started_at: 8.days.ago.utc]
          )
        end
      end

      context "batched job" do
        test "queues subsequent jobs for batching" do
          org = create(:organization).tap do |o|
            9.times do
              create(:repository, owner: o)
            end
          end

          CodeScanningRepositoriesDeviationDetectionJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: CodeScanningRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: CodeScanningRepositoriesDeviationDetectionJob do
                CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end
          end

          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "session lock" do
        test "does not allow consecutive jobs if session is still locked" do
          org = create(:organization)
          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once
          Session.any_instance.expects(:reset!).never

          Timecop.freeze do
            assert_performed_jobs 1, only: CodeScanningRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: CodeScanningRepositoriesDeviationDetectionJob do
                CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            assert Session.new(owner_id: org.id, type: "code_scanning_alert").locked?
          end

          Timecop.travel(1.day.from_now) do
            assert_enqueued_jobs 0, only: CodeScanningRepositoriesDeviationDetectionJob do
              CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end

            assert Session.new(owner_id: org.id, type: "code_scanning_alert").locked?
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
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once

          Timecop.freeze do
            assert_performed_jobs 1, only: CodeScanningRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: CodeScanningRepositoriesDeviationDetectionJob do
                CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            refute Session.new(owner_id: org.id, type: "code_scanning_alert").locked?
          end
        end

        test "reset session lock when retry attempts are exhausted" do
          org = create(:organization)
          CodeScanningRepositoriesDeviationDetectionJob.any_instance.stubs(:perform).raises(ActiveRecord::ConnectionFailed)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once

          assert_performed_jobs(5, only: [CodeScanningRepositoriesDeviationDetectionJob]) do
            perform_enqueued_jobs only: CodeScanningRepositoriesDeviationDetectionJob do
              CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "code_scanning_alert").locked?
        end

        test "reset session lock on non-retryable exceptions" do
          org = create(:organization)
          CodeScanningRepositoriesDeviationDetectionJob.any_instance.stubs(:perform).raises(ArgumentError.new("some error"))

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "code_scanning_alert"
            })
          ).once

          perform_enqueued_jobs only: CodeScanningRepositoriesDeviationDetectionJob do
            assert_raises ArgumentError do
              CodeScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "code_scanning_alert").locked?
        end
      end
    end
  end
end
