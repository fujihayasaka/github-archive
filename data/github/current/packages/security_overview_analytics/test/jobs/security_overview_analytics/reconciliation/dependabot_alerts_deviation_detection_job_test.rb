# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  module Reconciliation
    class DependabotAlertsDeviationDetectionJobTest < GitHub::TestCase
      include DogstatsTestHelpers
      include JobTestHelper

      Event = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent

      fixtures do
        @org = create(:business_plus_organization)
        @repo = create(:repository, owner: @org)
      end

      setup do
        TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
        Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(true)
        GitHub.logger.stubs(:info).returns(true)
        Session.any_instance.stubs(:locked?).returns(true)

        @last_reconciled = (Time.now - 7.days).utc
        @session_id = "#{@org.id}.#{(Time.now - 7.days).utc}"
        @stats_tags = ["metric_type:dependabot_alerts"].compact

        if GitHub.enterprise?
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
        end
      end

      context "#perform" do
        test "process all alerts if first reconciliation" do
          alert1 = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "vuln-1",
            affects: "package-1",
            repository: @repo,
          )

          alert2 = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "vuln-2",
            affects: "package-2",
            repository: @repo,
          )

          DependabotAlertsDeviationDetectionJob.any_instance.expects(:next_batch).once.returns([alert1, alert2])

          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
        end

        test "process only alerts updated since the last reconciliation if it's a subsequent run" do
          alert1 = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "vuln-1",
            affects: "package-1",
            repository: @repo,
          )

          alert2 = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "vuln-2",
            affects: "package-2",
            repository: @repo,
          )

          Timecop.freeze do
            now = Time.now.utc
            # Update the alert to advance the updated_at time
            alert2 = T.cast(alert2, RepositoryVulnerabilityAlert)
            alert2.touch

            DependabotAlertsDeviationDetectionJob.any_instance.expects(:next_batch).once.returns([alert2])

            assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
              DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: now)
            end
          end
        end

        test "reports and queues remediation for missing alert" do
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "vuln-1",
            affects: "package-1",
            repository: @repo,
          )

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.dependabot.alert_id": alert.id,
              "gh.security_overview_analytics.dependabot.alert_number": alert.number,
              "gh.security_overview_analytics.deviations": [:missing_alert]
            })
          ).once

          event_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: false)

          DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
            alert: event_payload,
            source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
            event_time: event_payload.updated_at&.to_time,
            force_rewrite: false,
            update_severity: false
          ).once

          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
        end

        test "reports and queues remediation for missing alert that's also missing initial revision" do
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "vuln-1",
            affects: "package-1",
            repository: @repo,
          )

          Timecop.freeze do
            now = Time.now.utc
            # Update the alert to advance the updated_at time
            alert = T.cast(alert, RepositoryVulnerabilityAlert)
            alert.touch

            # Assert both deviation reports
            GitHub.logger.expects(:info).with(
              "Deviation found.",
              has_entries({
                "gh.security_overview_analytics.dependabot.alert_id": alert.id,
                "gh.security_overview_analytics.dependabot.alert_number": alert.number,
                "gh.security_overview_analytics.deviations": [:missing_alert]
              })
            ).once

            GitHub.logger.expects(:info).with(
              "Deviation found.",
              has_entries({
                "gh.security_overview_analytics.dependabot.alert_id": alert.id,
                "gh.security_overview_analytics.dependabot.alert_number": alert.number,
                "gh.security_overview_analytics.deviations": [:missing_alert, :missing_initial_revision]
              })
            ).once

            updated_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: false)
            created_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: true)

            # Assert remediations queued with different event times
            DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
              alert: updated_payload,
              source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
              event_time: updated_payload.updated_at&.to_time,
              force_rewrite: false,
              update_severity: false
            ).once

            DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
              alert: created_payload,
              source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
              event_time: created_payload.created_at&.to_time,
              force_rewrite: false,
              update_severity: false
            ).once

            assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
              DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
            end
          end
        end

        test "skips missing initial revision if missing alert was updated before retention limit" do
          # `beginning_of_day` to avoid DST issues
          Timecop.freeze Time.now.utc.beginning_of_day do
            alert = create(:repository_vulnerability_alert,
              vulnerable_manifest_path: "vuln-1",
              affects: "package-1",
              repository: @repo,
              created_at: Date::RETENTION_DURATION.ago - 1.week,
              updated_at: Date::RETENTION_DURATION.ago - 1.day
            )

            # Assert both deviation reports
            GitHub.logger.expects(:info).with(
              "Deviation found.",
              has_entries({
                "gh.security_overview_analytics.dependabot.alert_id": alert.id,
                "gh.security_overview_analytics.dependabot.alert_number": alert.number,
                "gh.security_overview_analytics.deviations": [:missing_alert]
              })
            ).once

            GitHub.logger.expects(:info).with(
              "Deviation found.",
              has_entries({
                "gh.security_overview_analytics.dependabot.alert_id": alert.id,
                "gh.security_overview_analytics.dependabot.alert_number": alert.number,
                "gh.security_overview_analytics.deviations": [:missing_alert, :missing_initial_revision]
              })
              ).never

            updated_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: false)
            created_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: true)

            DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
              alert: updated_payload,
              source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
              event_time: updated_payload.updated_at&.to_time,
              force_rewrite: false,
              update_severity: false
            ).once

            DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
              alert: created_payload,
              source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
              event_time: updated_payload.created_at&.to_time,
              force_rewrite: false,
              update_severity: false
            ).never

            assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
              DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: nil)
            end
          end
        end

        test "reports and queues remediation for an existing alert that's missing initial revision" do
          vulnerable_version_range = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm")
          vulnerability = create(:vulnerability, severity: "high")
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range:,
            vulnerability:,
            affects: "package-2",
            repository: @repo,
          )

          Timecop.travel(1.day.from_now) do
            now = Time.now.utc
            # Update the alert to advance the updated_at time
            alert = T.cast(alert, RepositoryVulnerabilityAlert)
            alert.touch

            updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
            create_dbot_revision_from_alert(alert, @repo, updated_date_id)

            GitHub.logger.expects(:info).with(
              "Deviation found.",
              has_entries({
                "gh.security_overview_analytics.dependabot.alert_id": alert.id,
                "gh.security_overview_analytics.dependabot.alert_number": alert.number,
                "gh.security_overview_analytics.deviations": [:missing_initial_revision]
              })
            ).once

            event_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: true)

            # Assert remediations queued with different event times
            DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
              alert: event_payload,
              source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
              event_time: event_payload.created_at&.to_time,
              force_rewrite: false,
              update_severity: false
            ).once

            assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
              DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
            end
          end
        end

        test "reports and queues remediation for an existing alert with deviations" do
          vulnerable_version_range = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm")
          vulnerability = create(:vulnerability, severity: "high")
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range:,
            vulnerability:,
            affects: "package-2",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
          revision = create_dbot_revision_from_alert(alert, @repo, updated_date_id)
          revision.update!(alert_severity: :LOW, alert_resolved: true)

          GitHub.logger.expects(:info).with(
            "Deviation found.",
            has_entries({
              "gh.security_overview_analytics.dependabot.alert_id": alert.id,
              "gh.security_overview_analytics.dependabot.alert_number": alert.number,
              "gh.security_overview_analytics.deviations": [:alert_resolved, :alert_severity]
            })
          ).once

          event_payload = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: false)

          DependabotAlertRevisionIngestionJob.expects(:perform_later).with(
            alert: event_payload,
            source_event: Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT,
            event_time: event_payload.updated_at&.to_time,
            force_rewrite: true,
            update_severity: true
          ).once

          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
        end

        test "queues PostReconciliationRepoDeviationCountsJob", skip_enterprise: true do
          vulnerable_version_range = create(:vulnerable_version_range, affects: "react", fixed_in: "2", ecosystem: "npm")
          vulnerability = create(:vulnerability, severity: "high")
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range:,
            vulnerability:,
            affects: "package-1",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
          revision = create_dbot_revision_from_alert(alert, @repo, updated_date_id)

          vulnerable_version_range = create(:vulnerable_version_range, affects: "typescript", fixed_in: "1", ecosystem: "npm")
          vulnerability = create(:vulnerability, severity: "high")
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            vulnerable_version_range:,
            vulnerability:,
            affects: "package-2",
            repository: @repo,
          )

          updated_date_id = SecurityOverviewAnalytics::Date.id_from_time(alert.updated_at&.utc.to_time)
          revision = create_dbot_revision_from_alert(alert, @repo, updated_date_id)

          Timecop.freeze do
            assert_enqueued_with(
              job: PostReconciliationRepoDeviationCountsJob,
              at: 1.hour.from_now,
            ) do
              # 3 jobs get run even though there's only 2 alerts being considered because the has_next_batch? checks if the batch sizes are >= BATCH_SIZE
              assert_performed_jobs 3, only: DependabotAlertsDeviationDetectionJob do
                ::BatchedJob.stub_const(:BATCH_SIZE, 1) do
                  DependabotAlertsDeviationDetectionJob.perform_later(
                    repository_id: @repo.id,
                    session_id: @session_id,
                    last_session_started_at: @last_reconciled,
                  )
                end
              end
            end
          end
        end

        test "does not queue PostReconciliationRepoDeviationCountsJob in GHES", enterprise_only: true do
          Timecop.freeze do
            assert_no_performed_jobs only: PostReconciliationRepoDeviationCountsJob do
              DependabotAlertsDeviationDetectionJob.perform_later(
                repository_id: @repo.id,
                session_id: @session_id,
                last_session_started_at: @last_reconciled,
              )
            end
          end
        end

        context "when alert is withdrawn" do
          test "it does nothing if no revisions exist" do
            alert = create(:repository_vulnerability_alert,
              vulnerable_manifest_path: "manifest-1",
              affects: "package-1",
              repository: @repo,
              active: false,
              state: 10 # withdrawn
            )
            alert.touch
            alert_event = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: false)

            perform_enqueued_jobs only: DependabotAlertsDeviationDetectionJob do
              assert_nothing_raised do
                DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
              end
            end

            assert_empty DependabotAlertRevision.all
            refute_dogstats_increment "security_overview_analytics.reconciliation.deviation"
          end

          test "it purges existing revisions" do
            alert = create(:repository_vulnerability_alert,
              vulnerable_manifest_path: "manifest-1",
              affects: "package-1",
              repository: @repo,
              active: false,
              state: 10 # withdrawn
            )
            alert.touch
            alert_event = DependabotAlertRevision.create_event_payload(alert: alert, is_initial_event: false)

            revision = create_dbot_revision_from_alert(alert, @repo, Date.id_from_time(alert.updated_at))
            revision.update!(alert_resolved: false)

            assert_equal 1, DependabotAlertRevision.count

            perform_enqueued_jobs only: DependabotAlertsDeviationDetectionJob do
              assert_nothing_raised do
                DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
              end
            end

            assert_empty DependabotAlertRevision.all
            assert_dogstats_increment 1, "security_overview_analytics.reconciliation.deviation", tags: ["deviation:alert_withdrawn"]
          end
        end
      end

      context "#around_enqueue" do
        test "raises ArgumentError if missing repository_id" do
          assert_enqueued_jobs 0, only: DependabotAlertsDeviationDetectionJob do
            assert_raises ArgumentError do
              DependabotAlertsDeviationDetectionJob.perform_later(last_session_started_at: @last_reconciled)
            end
          end
        end
      end

      context "#around_perform" do
        test "stops the perform if feature not configured on GHES", enterprise_only: true do
          SecurityCenter::SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(false)
          DependabotAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          DependabotAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:feature_unavailable"]
        end

        test "stops the perform if repo was soft deleted" do
          DependabotAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          DependabotAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          repo = create(:deleted_repository, owner: @org)
          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:repository_deleted"]
        end

        test "stops the perform if tenant out of scope" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)

          DependabotAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          DependabotAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          org = create(:organization)
          repo = create(:repository, owner: org)
          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:owner_not_in_scope"]
        end

        test "stops the perform if tenant not initialized" do
          Initialization.any_instance.stubs(:initialized?).with(type: Initialization::Type::DependabotAlerts).returns(false)

          DependabotAlertsDeviationDetectionJob.any_instance.expects(:next_batch).never
          DependabotAlertsDeviationDetectionJob.any_instance.expects(:process_batch).never
          Session.any_instance.expects(:reset!).once

          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
          end
          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:tenant_not_initialized"]
        end

        test "stops the perform if session has been reset" do
          Session.any_instance.stubs(:locked?).returns(false)
          Session.any_instance.expects(:reset!).never

          assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id)
          end

          assert_dogstats_increment 1, "security_overview_analytics.reconciliation.skipped", tags: @stats_tags + ["reason:session_reset"]
        end
      end

      context "batched job" do
        test "queues subsequent jobs for batching" do
          9.times.each_with_index do |_, id|
            create(:repository_vulnerability_alert,
              vulnerable_manifest_path: "vuln-#{id}",
              affects: "package-#{id}",
              repository: @repo,
            )
          end

          DependabotAlertsDeviationDetectionJob.stub_const(:BATCH_SIZE, 5) do
            assert_performed_jobs 2, only: DependabotAlertsDeviationDetectionJob do
              perform_enqueued_jobs only: DependabotAlertsDeviationDetectionJob do
                DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
              end
            end
          end

          assert_dogstats_distribution 1, "batched_job.total_time.dist"
        end
      end

      context "hash lock" do
        test "does not allow concurrent jobs for the same input" do
          assert_enqueued_jobs 2, only: DependabotAlertsDeviationDetectionJob do
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: @session_id, last_session_started_at: @last_reconciled)
            DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id, session_id: "hohoho", last_session_started_at: @last_reconciled)
          end
        end
      end

      context "resiliency" do
        test "retries on standard conditions" do
          assert_retry_conditions(job: DependabotAlertsDeviationDetectionJob, args: [{ repository_id: @repo.id, session_id: "hohoho", last_session_started_at: @last_reconciled }])
        end
      end

      context "session lock" do
        test "reset session lock if job fails tenant validation" do
          Session.any_instance.unstub(:locked?)
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          Session.new(owner_id: @org.id, type: "dependabot_alerts").lock!

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": @org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          Timecop.freeze do
            assert_performed_jobs 1, only: DependabotAlertsDeviationDetectionJob do
              perform_enqueued_jobs only: DependabotAlertsDeviationDetectionJob do
                DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id)
              end
            end

            refute Session.new(owner_id: @org.id, type: "dependabot_alerts").locked?
          end
        end

        test "reset session lock when retry attempts are exhausted" do
          DependabotAlertsDeviationDetectionJob.any_instance.stubs(:perform).raises(ActiveRecord::ConnectionFailed)
          Session.any_instance.unstub(:locked?)
          Session.new(owner_id: @org.id, type: "dependabot_alerts").lock!

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": @org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once


          assert_performed_jobs(5, only: [DependabotAlertsDeviationDetectionJob]) do
            perform_enqueued_jobs only: DependabotAlertsDeviationDetectionJob do
              DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id)
            end
          end

          refute Session.new(owner_id: @org.id, type: "dependabot_alerts").locked?
        end

        test "reset session lock on non-retryable exceptions" do
          Session.any_instance.unstub(:locked?)
          Session.new(owner_id: @org.id, type: "dependabot_alerts").lock!
          DependabotAlertsDeviationDetectionJob.any_instance.stubs(:perform).raises(ArgumentError.new("some error"))

          GitHub.logger.expects(:info).with(
            "Session reset.",
            has_entries({
              "gh.owner.id": @org.id,
              "gh.security_overview_analytics.reconciliation.type": "dependabot_alerts"
            })
          ).once

          perform_enqueued_jobs only: DependabotAlertsDeviationDetectionJob do
            assert_raises ArgumentError do
              DependabotAlertsDeviationDetectionJob.perform_later(repository_id: @repo.id)
            end
          end

          refute Session.new(owner_id: @org.id, type: "dependabot_alerts").locked?
        end
      end

      sig { params(alert: ::RepositoryVulnerabilityAlert, repo: ::Repository, date_id: Integer).returns(DependabotAlertRevision) }
      def create_dbot_revision_from_alert(alert, repo, date_id)
        last_state_change_reason = alert.last_state_change_reason&.upcase&.to_sym
        alert_resolution = if last_state_change_reason.is_a?(Symbol)
          Event::LastStateChangeReason.resolve(last_state_change_reason) || Event::LastStateChangeReason::REASON_UNKNOWN
        end
        alert_resolution = nil if alert_resolution == Event::LastStateChangeReason::NO_REASON

        create(:security_overview_analytics_dependabot_alert_revision,
          repository_id: repo.id,
          date_id:,
          alert_number: alert.number,
          alert_resolved: !alert.open?,
          alert_resolved_at: !alert.open? ? alert.last_state_change_at : nil,
          alert_resolution:,
          alert_severity: alert.severity&.upcase&.to_sym,
          ghsa_id: alert.vulnerability&.ghsa_id,
          dependency_scope: alert.dependency_scope&.upcase&.to_sym,
          ecosystem: alert.ecosystem,
          package_name: alert.package_name
        )
      end
    end
  end
end
