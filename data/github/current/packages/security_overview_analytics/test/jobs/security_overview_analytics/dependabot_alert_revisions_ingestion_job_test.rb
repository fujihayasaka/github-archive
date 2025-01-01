# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class DependabotAlertRevisionIngestionJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include JobTestHelper

    Event = Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent

    fixtures do
      @org = create(:organization)
      @repo = create(:repository, owner: @org)

      @alert = create(:repository_vulnerability_alert,
        vulnerable_manifest_path: "package.json",
        affects: "react",
        repository: @repo,
      )
    end

    setup do
      Timecop.freeze do
        @now = Time.current.iso8601(3).to_time.utc
        @one_week_ago = 7.days.ago.iso8601(3).to_time.utc
        @one_hour_ago = 1.hour.ago.iso8601(3).to_time.utc
        @one_day_ago = 1.day.ago.iso8601(3).to_time.utc
      end
      @alert_event = DependabotAlertRevision.create_event_payload(alert: @alert, is_initial_event: false)

      TenantValidationHelper.stubs(:is_owner_in_scope?).returns(true)
    end

    context "#around_enqueue" do
      test "report and skip if alert id is missing" do
        alert_event = DependabotAlertRevision.create_event_payload(alert: @alert, is_initial_event: false)
        alert_event.repository_vulnerability_alert_id = 0

        GitHub.logger.expects(:info).with(
          "Upsert skipped.",
          has_entries({
            "gh.security_overview_analytics.job.reason": "missing_alert_identifier"
          })
        ).once

        assert_enqueued_jobs 0, only: DependabotAlertRevisionIngestionJob do
          DependabotAlertRevisionIngestionJob.perform_later(
            alert: alert_event,
            event_time: @now,
            source_event: "security_overview_analytics.test",
          )
        end

        assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.skipped", tags: ["reason:missing_alert_identifier"]
      end

      test "report and skip if alert number is missing" do
        alert_event = DependabotAlertRevision.create_event_payload(alert: @alert, is_initial_event: false)
        alert_event.repository_vulnerability_alert_number = 0

        GitHub.logger.expects(:info).with(
          "Upsert skipped.",
          has_entries({
            "gh.security_overview_analytics.job.reason": "missing_alert_identifier"
          })
        ).once

        assert_enqueued_jobs 0, only: DependabotAlertRevisionIngestionJob do
          DependabotAlertRevisionIngestionJob.perform_later(
            alert: alert_event,
            event_time: @now,
            source_event: "security_overview_analytics.test",
          )
        end

        assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.skipped", tags: ["reason:missing_alert_identifier"]
      end

      test "report and skip if repository id is missing" do
        alert_event = DependabotAlertRevision.create_event_payload(alert: @alert, is_initial_event: false)
        alert_event.repository_id = 0

        GitHub.logger.expects(:info).with(
          "Upsert skipped.",
          has_entries({
            "gh.security_overview_analytics.job.reason": "missing_alert_identifier"
          })
        ).once

        assert_enqueued_jobs 0, only: DependabotAlertRevisionIngestionJob do
          DependabotAlertRevisionIngestionJob.perform_later(
            alert: alert_event,
            event_time: @now,
            source_event: "security_overview_analytics.test",
          )
        end

        assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.skipped", tags: ["reason:missing_alert_identifier"]
      end
    end

    context "#around_perform" do
      context "when the repository is soft-deleted" do
        test "it skips performing the upsert" do
          DependabotAlertRevision.expects(:upsert_revision).never

          repo = create(:deleted_repository, owner: @org)
          alert = create(:repository_vulnerability_alert, vulnerable_manifest_path: "package.json", affects: "react", repository: repo)
          alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)

          assert_performed_jobs(1, only: DependabotAlertRevisionIngestionJob) do
            DependabotAlertRevisionIngestionJob.perform_later(
              alert: alert_event,
              event_time: @now,
              source_event: "security_overview_analytics.test",
            )
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.skipped", tags: ["reason:repository_deleted"]
        end
      end

      context "when owner is not an org" do
        test "it skips performing the upsert" do
          user = create(:user)
          user_repo = create(:repository, owner: user, name: "foo")

          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package-2",
            affects: "react-2",
            repository: user_repo,
          )
          alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)

          DependabotAlertRevision.expects(:upsert_revision).never

          assert_performed_jobs(1, only: DependabotAlertRevisionIngestionJob) do
            DependabotAlertRevisionIngestionJob.perform_later(
              alert: alert_event,
              event_time: @now,
              source_event: "security_overview_analytics.test",
            )
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.skipped", tags: ["reason:not_org_owned_repo"]
        end
      end

      context "when org is not in scope" do
        test "it skips performing the upsert" do
          TenantValidationHelper.stubs(:is_owner_in_scope?).returns(false)
          DependabotAlertRevision.expects(:upsert_revision).never

          assert_performed_jobs(1, only: DependabotAlertRevisionIngestionJob) do
            DependabotAlertRevisionIngestionJob.perform_later(
              alert: @alert_event,
              event_time: @now,
              source_event: "security_overview_analytics.test",
            )
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.skipped", tags: ["reason:tenant_not_in_scope"]
        end
      end
    end

    context "#perform" do
      test "upserts initial revision" do
        Timecop.freeze do
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            affects: "react",
            repository: @repo,
            created_at: @one_day_ago,
            updated_at: @now
          )

          event_time = alert.created_at&.to_time.utc
          alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: true)

          DependabotAlertRevision.expects(:upsert_revision).with(
            DependabotAlertRevision::UpdatePayload.new(
              alert_resolved: false,
              alert_resolution: nil,
              alert_severity: T.must(alert.severity&.upcase&.to_sym),
              ghsa_id: alert.vulnerability.ghsa_id,
              dependency_scope: T.must(alert.dependency_scope&.upcase&.to_sym),
              package_name: alert.package_name,
              ecosystem: alert.ecosystem,
              alert_created_at: alert.created_at&.to_time&.utc,
              alert_updated_at: event_time,
            ),
            repository_id: @repo.id,
            alert_number: alert.number,
            force_rewrite: false,
          )

          perform_enqueued_jobs only: DependabotAlertRevisionIngestionJob do
            assert_nothing_raised do
              DependabotAlertRevisionIngestionJob.perform_later(
                alert: alert_event,
                event_time: event_time,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.success"
        end
      end

      test "upserts latest revision" do
        Timecop.freeze do
          alert = create(:repository_vulnerability_alert,
            :fixed,
            vulnerable_manifest_path: "package.json",
            affects: "react",
            repository: @repo,
            created_at: @one_day_ago,
            updated_at: @now
          )

          event_time = alert.updated_at&.to_time.utc
          alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)

          DependabotAlertRevision.expects(:upsert_revision).with(
            DependabotAlertRevision::UpdatePayload.new(
              alert_resolved: true,
              alert_resolved_at: alert.last_state_change_at&.iso8601(3)&.to_time&.utc,
              alert_resolution: Event::LastStateChangeReason::DEPENDENCY_CHANGED,
              alert_severity: T.must(alert.severity&.upcase&.to_sym),
              ghsa_id: alert.vulnerability.ghsa_id,
              dependency_scope: T.must(alert.dependency_scope&.upcase&.to_sym),
              package_name: alert.package_name,
              ecosystem: alert.ecosystem,
              alert_created_at: alert.created_at&.to_time&.utc,
              alert_updated_at: event_time,
            ),
            repository_id: @repo.id,
            alert_number: alert.number,
            force_rewrite: false,
          )

          perform_enqueued_jobs only: DependabotAlertRevisionIngestionJob do
            assert_nothing_raised do
              DependabotAlertRevisionIngestionJob.perform_later(
                alert: alert_event,
                event_time: event_time,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.success"
        end
      end

      test "upserts latest revision and updates all revisions' severities if update_severity is true" do
        Timecop.freeze do
          alert = create(:repository_vulnerability_alert,
            :fixed,
            vulnerable_manifest_path: "package.json",
            affects: "react",
            severity: "low",
            repository: @repo,
            created_at: @one_day_ago,
            updated_at: @now
          )

          event_time = alert.updated_at&.to_time.utc
          alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)

          DependabotAlertRevision.expects(:upsert_revision).with(
            DependabotAlertRevision::UpdatePayload.new(
              alert_resolved: true,
              alert_resolved_at: alert.last_state_change_at&.iso8601(3)&.to_time&.utc,
              alert_resolution: Event::LastStateChangeReason::DEPENDENCY_CHANGED,
              alert_severity: T.must(alert.severity&.upcase&.to_sym),
              ghsa_id: alert.vulnerability.ghsa_id,
              dependency_scope: T.must(alert.dependency_scope&.upcase&.to_sym),
              package_name: alert.package_name,
              ecosystem: alert.ecosystem,
              alert_created_at: alert.created_at&.to_time&.utc,
              alert_updated_at: event_time,
            ),
            repository_id: @repo.id,
            alert_number: alert.number,
            force_rewrite: false,
          )

          DependabotAlertRevision.expects(:update_severities).with(
            alert.severity&.upcase&.to_sym,
            repository_id: @repo.id,
            alert_number: alert.number,
          )

          perform_enqueued_jobs only: DependabotAlertRevisionIngestionJob do
            assert_nothing_raised do
              DependabotAlertRevisionIngestionJob.perform_later(
                alert: alert_event,
                event_time: event_time,
                source_event: "security_overview_analytics.test",
                update_severity: true
              )
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.success"
        end
      end

      test "can upserts alert revision with force_rewrite" do
        Timecop.freeze do
          alert = create(:repository_vulnerability_alert,
            vulnerable_manifest_path: "package.json",
            affects: "react",
            repository: @repo,
            created_at: @one_day_ago,
            updated_at: @now
          )

          event_time = alert.created_at&.to_time.utc
          alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: true)

          DependabotAlertRevision.expects(:upsert_revision).with(anything, has_entries(force_rewrite: true)).once

          perform_enqueued_jobs only: DependabotAlertRevisionIngestionJob do
            assert_nothing_raised do
              DependabotAlertRevisionIngestionJob.perform_later(
                alert: alert_event,
                event_time: event_time,
                force_rewrite: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.dependabot_alert_revision_ingestion.success"
        end
      end

      context "telemetry" do
        context "when source event is incremental" do
          test "emits repository updated metric" do
            source_event = "hydro.schemas.github.security_alerts.v1.repositoryvulnerabilityalertlifecycleevent_create"
            alert = create(:repository_vulnerability_alert, repository: @repo, created_at: @one_day_ago, updated_at: @now)
            alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)
            DependabotAlertRevisionIngestionJob.perform_now(alert: alert_event, event_time: @now, source_event:)
            assert_dogstats_distribution(1, "security_overview_analytics.updated.dist", tags: ["source_event:#{source_event}"])
          end
        end

        context "when source event is initialization" do
          test "emits repository updated metric" do
            source_event = Initialization::TenantBaseJob::INITIALIZATION_EVENT
            alert = create(:repository_vulnerability_alert, repository: @repo, created_at: @one_day_ago, updated_at: @now)
            alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)
            DependabotAlertRevisionIngestionJob.perform_now(alert: alert_event, event_time: @now, source_event:)
            refute_dogstats_distribution("security_overview_analytics.updated.dist")
          end
        end

        context "when source event is reconciliation" do
          test "emits repository updated metric" do
            source_event = Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT
            alert = create(:repository_vulnerability_alert, repository: @repo, created_at: @one_day_ago, updated_at: @now)
            alert_event = DependabotAlertRevision.create_event_payload(alert:, is_initial_event: false)
            DependabotAlertRevisionIngestionJob.perform_now(alert: alert_event, event_time: @now, source_event:)
            refute_dogstats_distribution("security_overview_analytics.updated.dist")
          end
        end
      end
    end

    def create_dbot_revision_from_alert(alert, repo, date_id)
      last_state_change_reason =
        if alert.open? && alert.last_state_change_reason.nil?
          Event::LastStateChangeReason::NO_REASON
        else
          alert.last_state_change_reason&.upcase&.to_sym
        end

      create(:security_overview_analytics_dependabot_alert_revision,
        repository_id: repo.id,
        date_id:,
        alert_number: alert.number,
        alert_resolved: !alert.open?,
        alert_resolved_at: !alert.open? ? alert.last_state_change_at : nil,
        alert_resolution: last_state_change_reason || Event::LastStateChangeReason::REASON_UNKNOWN,
        alert_severity: alert.severity.upcase.to_sym,
        ghsa_id: alert.vulnerability.ghsa_id,
        dependency_scope: alert.dependency_scope.upcase.to_sym,
        ecosystem: alert.ecosystem,
        package_name: alert.package_name
      )
    end
  end
end
