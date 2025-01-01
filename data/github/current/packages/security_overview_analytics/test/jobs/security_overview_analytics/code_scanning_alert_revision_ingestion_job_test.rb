# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboscan"

module SecurityOverviewAnalytics
  class CodeScanningAlertRevisionIngestionJobTest < GitHub::TestCase
    include DogstatsTestHelpers

    TurboscanInsightsAlert = ::Turboscan::Proto::InsightsAlert

    fixtures do
      @org = create(:organization)
      @repo = create(:repository, owner: @org)
    end

    setup do
      Timecop.freeze do
        @now = Time.current.iso8601(3).to_time.utc
        @two_days_ago = 2.days.ago.iso8601(3).to_time.utc
        @date_id = ::SecurityOverviewAnalytics::Date.id_from_time(@now)
      end

      TenantValidationHelper.stubs(:should_handle_code_scanning_alert_events?).returns(true)
    end

    context "#perform" do
      context "when alert is updated" do
        test "it invokes upsert logic with event payload arguments when read flags are either both off or on" do
          repo_meta = create(:security_overview_analytics_repository)

          alert = TurboscanInsightsAlert.new(
            id: 42,
            number: 42,
            repository_id: repo_meta.repository_id,
            created_at: @two_days_ago,
            updated_at: @now,
            resolution: :NO_RESOLUTION,
            rule_name: "Uncontrolled data used in path expression",
            rule_sarif_identifier: "rb/path-injection",
            tool_name: "CodeQL",
            severity: :HIGH,
            closed_at: nil,
            closed: false,
            present_on_default_ref: true,
          )

          # This should also pass in TEST_ALL_FEATURES_RUN = 1 since when both read_alert_id and read_alert_number flags
          # are on, we fall back to the default behavior of using alert_number == alert_id
          CodeScanningAlertRevision.expects(:upsert_revision).with(
            CodeScanningAlertRevision::UpdatePayload.new(
              alert_created_at: alert.created_at&.to_time.utc,
              alert_updated_at: alert.updated_at&.to_time.utc,
              alert_severity: alert.severity.to_s,
              tool: alert.tool_name,
              rule_sarif_identifier: alert.rule_sarif_identifier,
              alert_resolved: alert.closed,
              alert_resolved_at: alert.closed_at&.to_time&.utc,
              alert_resolution: alert.closed ? T.unsafe(alert.resolution).to_i : nil,
              alert_id: alert.id,
            ),
            repository_id: repo_meta.repository_id,
            alert_number: alert.id,
            date_id: Date.id_from_time(alert.updated_at&.to_time.utc),
            force_rewrite: false,
            alert_id: nil,
          )

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end

        test "it invokes upsert logic with event payload arguments and alert_number == number iff write_alert_number flag is on and one of read_alert_number or read_alert_id is on" do
          FeatureFlagHelper.stubs(:code_scanning_write_alert_number?).returns(true)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(true)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(false)
          repo_meta = create(:security_overview_analytics_repository)

          alert = TurboscanInsightsAlert.new(
            id: 42,
            number: 10,
            repository_id: repo_meta.repository_id,
            created_at: @two_days_ago,
            updated_at: @now,
            resolution: :NO_RESOLUTION,
            rule_name: "Uncontrolled data used in path expression",
            rule_sarif_identifier: "rb/path-injection",
            tool_name: "CodeQL",
            severity: :HIGH,
            closed_at: nil,
            closed: false,
            present_on_default_ref: true,
          )

          CodeScanningAlertRevision.expects(:upsert_revision).with(
            CodeScanningAlertRevision::UpdatePayload.new(
              alert_created_at: alert.created_at&.to_time.utc,
              alert_updated_at: alert.updated_at&.to_time.utc,
              alert_severity: alert.severity.to_s,
              tool: alert.tool_name,
              rule_sarif_identifier: alert.rule_sarif_identifier,
              alert_resolved: alert.closed,
              alert_resolved_at: alert.closed_at&.to_time&.utc,
              alert_resolution: alert.closed ? T.unsafe(alert.resolution).to_i : nil,
              alert_id: alert.id,
            ),
            repository_id: repo_meta.repository_id,
            alert_number: alert.number,
            date_id: Date.id_from_time(alert.updated_at&.to_time.utc),
            force_rewrite: false,
            alert_id: nil,
          )

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(false)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(true)

          CodeScanningAlertRevision.expects(:upsert_revision).with(
            CodeScanningAlertRevision::UpdatePayload.new(
              alert_created_at: alert.created_at&.to_time.utc,
              alert_updated_at: alert.updated_at&.to_time.utc,
              alert_severity: alert.severity.to_s,
              tool: alert.tool_name,
              rule_sarif_identifier: alert.rule_sarif_identifier,
              alert_resolved: alert.closed,
              alert_resolved_at: alert.closed_at&.to_time&.utc,
              alert_resolution: alert.closed ? T.unsafe(alert.resolution).to_i : nil,
              alert_id: alert.id,
            ),
            repository_id: repo_meta.repository_id,
            alert_number: alert.number,
            date_id: Date.id_from_time(alert.updated_at&.to_time.utc),
            force_rewrite: false,
            alert_id: alert.id,
          )

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end

        test "it invokes upsert logic with event payload arguments and alert_id iff read_alert_id flag is on and read_alert_number flag is off" do
          FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(true)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(false)
          FeatureFlagHelper.stubs(:code_scanning_write_alert_number?).returns(true)
          repo_meta = create(:security_overview_analytics_repository)

          alert = TurboscanInsightsAlert.new(
            id: 42,
            number: 10,
            repository_id: repo_meta.repository_id,
            created_at: @two_days_ago,
            updated_at: @now,
            resolution: :NO_RESOLUTION,
            rule_name: "Uncontrolled data used in path expression",
            rule_sarif_identifier: "rb/path-injection",
            tool_name: "CodeQL",
            severity: :HIGH,
            closed_at: nil,
            closed: false,
            present_on_default_ref: true,
          )

          CodeScanningAlertRevision.expects(:upsert_revision).with(
            CodeScanningAlertRevision::UpdatePayload.new(
              alert_created_at: alert.created_at&.to_time.utc,
              alert_updated_at: alert.updated_at&.to_time.utc,
              alert_severity: alert.severity.to_s,
              tool: alert.tool_name,
              rule_sarif_identifier: alert.rule_sarif_identifier,
              alert_resolved: alert.closed,
              alert_resolved_at: alert.closed_at&.to_time&.utc,
              alert_resolution: alert.closed ? T.unsafe(alert.resolution).to_i : nil,
              alert_id: alert.id,
            ),
            repository_id: repo_meta.repository_id,
            alert_number: alert.number,
            date_id: Date.id_from_time(alert.updated_at&.to_time.utc),
            force_rewrite: false,
            alert_id: alert.id,
          )

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end

        test "can upserts alert revision with force_rewrite" do
          repo_meta = create(:security_overview_analytics_repository)

          alert = TurboscanInsightsAlert.new(
            id: 42,
            number: 42,
            repository_id: repo_meta.repository_id,
            created_at: @two_days_ago,
            updated_at: @now,
            resolution: :NO_RESOLUTION,
            rule_name: "Uncontrolled data used in path expression",
            rule_sarif_identifier: "rb/path-injection",
            tool_name: "CodeQL",
            severity: :HIGH,
            closed_at: nil,
            closed: false,
            present_on_default_ref: true,
          )

          CodeScanningAlertRevision.expects(:upsert_revision).with(anything, has_entries(force_rewrite: true)).once

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                force_rewrite: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end
      end

      context "when alert is deleted" do
        test "it invokes delete logic for alert revisions when read flags are either both off or on" do
          # This should also pass in TEST_ALL_FEATURES_RUN = 1 since when both read_alert_id and read_alert_number flags
          # are on, we fall back to the default behavior of using alert_number == alert_id
          CodeScanningAlertRevision.expects(:delete_revisions)
            .with(has_entries(repository_id: @repo.id, alert_number: 111, alert_id: nil))
            .once

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  repository_id: @repo.id,
                  id: 111,
                  number: 111
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end

        test "it invokes delete logic for alert revisions with alert_number == number iff write_alert_number flag is on and one of read_alert_number or read_alert_id is on" do
          FeatureFlagHelper.stubs(:code_scanning_write_alert_number?).returns(true)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(true)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(false)

          CodeScanningAlertRevision.expects(:delete_revisions)
            .with(has_entries(repository_id: @repo.id, alert_number: 30, alert_id: nil))
            .once

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  repository_id: @repo.id,
                  id: 111,
                  number: 30,
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(false)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(true)

          CodeScanningAlertRevision.expects(:delete_revisions)
            .with(has_entries(repository_id: @repo.id, alert_number: 30, alert_id: 111))
            .once

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  repository_id: @repo.id,
                  id: 111,
                  number: 30,
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end

        test "it invokes delete logic for alert revisions with alert_id iff read_alert_id flag is on and read_alert_number flag is off" do
          FeatureFlagHelper.stubs(:code_scanning_read_alert_id?).returns(true)
          FeatureFlagHelper.stubs(:code_scanning_read_alert_number?).returns(false)
          FeatureFlagHelper.stubs(:code_scanning_write_alert_number?).returns(true)

          CodeScanningAlertRevision.expects(:delete_revisions)
            .with(has_entries(repository_id: @repo.id, alert_number: 30, alert_id: 111))
            .once

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  repository_id: @repo.id,
                  id: 111,
                  number: 30,
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end
        end

        test "raises an error and skips upsert if alert doesn't have a number" do
          FeatureFlagHelper.stubs(:code_scanning_write_alert_number?).returns(true)

          alert = TurboscanInsightsAlert.new(
            repository_id: @repo.id,
            id: 111,
            number: 0,
          )
          CodeScanningAlertRevision.expects(:upsert_revision).never

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_raises CodeScanningAlertRevisionIngestionJob::NoAlertNumberError do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning.alert_without_number"
        end

        test "raises an error and skips delete if alert doesn't have a number" do
          FeatureFlagHelper.stubs(:code_scanning_write_alert_number?).returns(true)

          alert = TurboscanInsightsAlert.new(
            repository_id: @repo.id,
            id: 111,
            number: 0,
          )

          CodeScanningAlertRevision.expects(:delete_revisions).never

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_raises CodeScanningAlertRevisionIngestionJob::NoAlertNumberError do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                date_id: @date_id,
                event_time: @now,
                deleted: true,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.code_scanning.alert_without_number"
        end
      end

      context "when payload does not contain repository_id" do
        test "it does nothing" do
          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  # no repository_id attribute
                  id: 111,
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_empty CodeScanningAlertRevision.all
          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_alert_revision_ingestion.skipped", tags: ["reason:repository_not_found"]
        end
      end

      context "when repository is soft-deleted" do
        test "it does nothing" do
          repo = create(:deleted_repository, owner: @org)
          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  repository_id: repo.id,
                  id: 111,
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_empty CodeScanningAlertRevision.all
          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_alert_revision_ingestion.skipped", tags: ["reason:repository_deleted"]
        end
      end

      context "when tenant is not in scope" do
        test "it does nothing" do
          TenantValidationHelper.stubs(:should_handle_code_scanning_alert_events?).returns(false)

          perform_enqueued_jobs only: CodeScanningAlertRevisionIngestionJob do
            assert_nothing_raised do
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert: TurboscanInsightsAlert.new(
                  repository_id: @repo.id,
                  id: 111,
                ),
                date_id: @date_id,
                event_time: @now,
                deleted: false,
                source_event: "security_overview_analytics.test",
              )
            end
          end

          assert_empty CodeScanningAlertRevision.all
          assert_dogstats_increment 1, "security_overview_analytics.code_scanning_alert_revision_ingestion.skipped", tags: ["reason:tenant_not_in_scope"]
        end
      end

      context "telemetry" do
        context "when source event is incremental" do
          test "emits repository updated metric" do
            source_event = "hydro.schemas.github.security_center.v0.insightsentitybatch.code_scanning_alert_upsert"
            alert = TurboscanInsightsAlert.new(id: 42, number: 42, repository_id: @repo.id, created_at: @two_days_ago, updated_at: @now)
            CodeScanningAlertRevisionIngestionJob.perform_now(alert:, date_id: @date_id, event_time: @now, deleted: false, source_event:)
            assert_dogstats_distribution(1, "security_overview_analytics.updated.dist", tags: ["source_event:#{source_event}"])
          end
        end

        context "when source event is initialization" do
          test "emits repository updated metric" do
            source_event = Initialization::TenantBaseJob::INITIALIZATION_EVENT
            alert = TurboscanInsightsAlert.new(id: 42, number: 42, repository_id: @repo.id, created_at: @two_days_ago, updated_at: @now)
            CodeScanningAlertRevisionIngestionJob.perform_now(alert:, date_id: @date_id, event_time: @now, deleted: false, source_event:)
            refute_dogstats_distribution("security_overview_analytics.updated.dist")
          end
        end

        context "when source event is reconciliation" do
          test "emits repository updated metric" do
            source_event = Reconciliation::OrganizationReconciliationJob::RECONCILIATION_EVENT
            alert = TurboscanInsightsAlert.new(id: 42, number: 42, repository_id: @repo.id, created_at: @two_days_ago, updated_at: @now)
            CodeScanningAlertRevisionIngestionJob.perform_now(alert:, date_id: @date_id, event_time: @now, deleted: false, source_event:)
            refute_dogstats_distribution("security_overview_analytics.updated.dist")
          end
        end
      end
    end
  end
end
