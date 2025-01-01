# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "secret_scanning_proto"

module SecurityOverviewAnalytics
  module Reconciliation
    class SecretScanningRepositoriesDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
      SecretScanningBackfillResponse = ::GitHub::Proto::SecretScanning::Metrics::V1::GetAlertsForInsightsBackfillRequestResponse

      setup do
        @stats_tags = ["metric_type:secret_scanning_alerts"]
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(true)
        # Stub info logging, otherwise we'll have to separately assert "Session locked" in every test.
        GitHub.logger.stubs(:info).returns(true)

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(true)
        end
      end

      context "#perform with organization_id" do
        test "can enqueue fanout jobs successfully" do
          alert_revision = create(:soa_secret_scanning_alert_revision)
          another_repo = create(:repository, owner: alert_revision.repository.owner)
          organization_id = alert_revision.repository.owner.id

          assert_enqueued_jobs 2, only: SecretScanningAlertsDeviationDetectionJob do
            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
            end
          end
        end

        test "queues alerts deviation detection job" do
          alert_revision = create(:soa_secret_scanning_alert_revision)
          SecretScanningAlertsDeviationDetectionJob.expects(:perform_later).with(
            repository_id: alert_revision.repository_id,
            last_session_started_at: nil
          ).once
          Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).never

          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: alert_revision.repository.owner.id)
          end
        end

        test "queues alerts initialization job if repo is not tracked in revisions table" do
          org = create(:organization)
          repo = create(:repository, owner: org)
          Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).never
          SecretScanningAlertsDeviationDetectionJob.expects(:perform_later).with(
            repository_id: repo.id,
            last_session_started_at: nil
          ).once

          last_session_started_at = Time.now
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
          end
        end

        test "does not enqueue alerts deviation detection job if no repositories found" do
          SecretScanningAlertsDeviationDetectionJob.expects(:perform_later).never
          org = create(:organization)
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
          end
        end
      end

      context "#perform with owner_id" do
        test "can enqueue fanout jobs successfully" do
          alert_revision = create(:soa_secret_scanning_alert_revision)
          another_repo = create(:repository, owner: alert_revision.repository.owner)
          organization_id = alert_revision.repository.owner.id

          assert_enqueued_jobs 2, only: SecretScanningAlertsDeviationDetectionJob do
            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: organization_id)
            end
          end
        end

        test "queues alerts deviation detection job" do
          alert_revision = create(:soa_secret_scanning_alert_revision)
          SecretScanningAlertsDeviationDetectionJob.expects(:perform_later).with(
            repository_id: alert_revision.repository_id,
            last_session_started_at: nil
          ).once
          Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).never

          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: alert_revision.repository.owner.id)
          end
        end

        test "queues alerts initialization job if repo is not tracked in revisions table" do
          org = create(:organization)
          repo = create(:repository, owner: org)
          Initialization::Repositories::SecretScanningAlertsJob.expects(:perform_later).never
          SecretScanningAlertsDeviationDetectionJob.expects(:perform_later).with(
            repository_id: repo.id,
            last_session_started_at: nil
          ).once

          last_session_started_at = Time.now
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id)
          end
        end

        test "does not enqueue alerts deviation detection job if no repositories found" do
          SecretScanningAlertsDeviationDetectionJob.expects(:perform_later).never
          org = create(:organization)
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id)
          end
        end
      end

      context "#around_enqueue" do
        test "raises ArgumentError if missing organization_id and owner_id" do
          assert_enqueued_jobs 0, only: SecretScanningRepositoriesDeviationDetectionJob do
            assert_raises ArgumentError do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later
            end
          end
        end
      end

      context "#around_perform with organization_id" do
        test "stops the perform if feature not configured on GHES", enterprise_only: true do
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)

          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          alert_revision = create(:soa_secret_scanning_alert_revision)
          another_repo = create(:repository, owner: alert_revision.repository.owner)
          organization_id = alert_revision.repository.owner.id
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:feature_unavailable"]
        end

        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(false)

          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "code_scanning_alert")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id, session_started_at: Time.now.utc)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "#around_perform with owner_id" do
        test "stops the perform if feature not configured on GHES", enterprise_only: true do
          SecurityCenter::SecurityFeatures.stubs(:secret_scanning_enabled_for_instance?).returns(false)

          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          alert_revision = create(:soa_secret_scanning_alert_revision)
          another_repo = create(:repository, owner: alert_revision.repository.owner)
          owner_id = alert_revision.repository.owner.id
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id:)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:feature_unavailable"]
        end

        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::SecretScanningAlert).returns(false)

          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:next_batch).never
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
            SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          org = create(:organization)
          session = Session.new(owner_id: org.id, type: "code_scanning_alert")
          session.lock!

          Timecop.travel(10.days.from_now) do
            timestamps = session.lock!
            session.reset!(last_session_started_at: timestamps[:last_session_started_at])

            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: nil, owner_id: org.id, session_started_at: Time.now.utc)
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

          SecretScanningRepositoriesDeviationDetectionJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: SecretScanningRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: SecretScanningRepositoriesDeviationDetectionJob do
                SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
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

          assert_retry_conditions(job: SecretScanningRepositoriesDeviationDetectionJob, args: [{ organization_id: org.id, session_started_at: Time.now.utc }])
        end
      end

      context "session lock" do
        test "can set ttl on session lock successfully" do
          alert_revision = create(:soa_secret_scanning_alert_revision)
          organization_id = alert_revision.repository.owner.id
          now = Time.now

          Timecop.freeze(now) do
            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
            end

            session = Session.new(owner_id: organization_id, type: Initialization::Type::SecretScanningAlert.serialize)
            assert session.locked?
            assert_equal 14.days.from_now.to_time.floor, SecurityCenter::KV.store.ttl(session.session_key).value { nil }
          end
        end

        test "does not move ttl on future session" do
          alert_revision = create(:soa_secret_scanning_alert_revision)
          organization_id = alert_revision.repository.owner.id
          now = Time.now

          Timecop.freeze(now) do
            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
            end

            session = Session.new(owner_id: organization_id, type: Initialization::Type::SecretScanningAlert.serialize)
            assert session.locked?
            expected_ttl = SecurityCenter::KV.store.ttl(session.session_key).value { nil }
            assert_equal 14.days.from_now.to_time.floor, expected_ttl

            Timecop.freeze(10.days.from_now.to_time) do
              assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
                SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id:)
              end
              refute_dogstats_increment "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_locked"]

              session = Session.new(owner_id: organization_id, type: Initialization::Type::SecretScanningAlert.serialize)
              assert session.locked?
              assert_equal expected_ttl, SecurityCenter::KV.store.ttl(session.session_key).value { nil }
            end
          end
        end

        test "does not allow consecutive jobs if session is still locked" do
          org = create(:organization)
          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once
          Session.any_instance.expects(:reset!).never

          Timecop.freeze do
            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: SecretScanningRepositoriesDeviationDetectionJob do
                SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            assert Session.new(owner_id: org.id, type: "secret_scanning_alert").locked?
          end

          Timecop.travel(1.hour.from_now) do
            assert_enqueued_jobs 0, only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end

            assert Session.new(owner_id: org.id, type: "secret_scanning_alert").locked?
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
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once

          Timecop.freeze do
            assert_performed_jobs 1, only: SecretScanningRepositoriesDeviationDetectionJob do
              perform_enqueued_jobs only: SecretScanningRepositoriesDeviationDetectionJob do
                SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
              end
            end

            refute Session.new(owner_id: org.id, type: "secret_scanning_alert").locked?
          end
        end

        test "reset session lock when retry attempts are exhausted" do
          org = create(:organization)
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.stubs(:perform).raises(ActiveRecord::ConnectionFailed)

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once

          assert_performed_jobs(5, only: [SecretScanningRepositoriesDeviationDetectionJob]) do
            perform_enqueued_jobs only: SecretScanningRepositoriesDeviationDetectionJob do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "secret_scanning_alert").locked?
        end

        test "reset session lock on non-retryable exceptions" do
          org = create(:organization)
          SecretScanningRepositoriesDeviationDetectionJob.any_instance.stubs(:perform).raises(ArgumentError.new("some error"))

          GitHub.logger.expects(:info).with(
            "Session locked.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": org.id,
              "gh.security_overview_analytics.reconciliation.type": "secret_scanning_alert"
            })
          ).once

          perform_enqueued_jobs only: SecretScanningRepositoriesDeviationDetectionJob do
            assert_raises ArgumentError do
              SecretScanningRepositoriesDeviationDetectionJob.perform_later(organization_id: org.id)
            end
          end

          refute Session.new(owner_id: org.id, type: "secret_scanning_alert").locked?
        end
      end
    end
  end
end
